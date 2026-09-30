defmodule GradePush.Assignments do
  @moduledoc "Assignment setup, invitations, teams, and repository provisioning state."

  import Ecto.Query

  alias GradePush.Accounts
  alias GradePush.Accounts.User

  alias GradePush.Assignments.{
    Assignment,
    AssignmentTest,
    Invitation,
    Repository,
    Subject,
    Team,
    TeamMember
  }

  alias GradePush.Classrooms
  alias GradePush.Classrooms.{Classroom, ClassroomStudent, GitHubConnection}
  alias GradePush.Crypto
  alias GradePush.Repo
  alias GradePush.Submissions
  alias GradePush.Teaching.Token
  alias GradePush.Workers.ProvisionAssignmentRepository
  alias GradePush.Workers.SyncAssignmentRepositoryAccess

  @locked_after_acceptance ~w(kind team_mode team_size template_repository repository_visibility autograding_enabled tests)
  @normalized_keys Map.new(
                     ~w(
    title instructions kind team_mode team_size deadline_at deadline cutoff_enabled cutoff
    template_repository template repository_name_pattern repository_visibility autograding_enabled
    autograding tests name description type points timeout_seconds command path input expected
    team_id team_name
  ),
                     fn key -> {key, String.to_existing_atom(key)} end
                   )

  @doc "Lists assignments in a classroom taught by the actor, including accepted subject counts."
  def list_assignments(%User{} = actor, classroom_id) do
    with {:ok, classroom} <- Classrooms.classroom_for_teacher(actor, classroom_id) do
      assignments =
        from(a in Assignment,
          where: a.classroom_id == ^classroom.id and is_nil(a.archived_at),
          order_by: [asc: a.inserted_at],
          preload: [:tests]
        )
        |> Repo.all()

      counts = subject_counts(Enum.map(assignments, & &1.id))

      {:ok,
       Enum.map(assignments, fn assignment ->
         %{assignment | submissions_count: Map.get(counts, assignment.id, 0)}
       end)}
    end
  end

  def list_assignments(_, _), do: {:error, :unauthorized}

  @doc "Fetches one assignment scoped to a classroom the actor teaches."
  def get_assignment(%User{} = actor, classroom_id, slug) do
    with {:ok, classroom} <- Classrooms.classroom_for_teacher(actor, classroom_id),
         %Assignment{} = assignment <-
           Repo.get_by(Assignment, classroom_id: classroom.id, slug: slug) do
      {:ok, preload_assignment(assignment)}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def get_assignment(_, _, _), do: {:error, :unauthorized}

  @doc "Creates and publishes an assignment with its immutable initial autograding test set."
  def create_assignment(%User{} = actor, classroom_id, attrs) do
    with {:ok, classroom} <- Classrooms.classroom_for_teacher(actor, classroom_id),
         attrs <- normalize_attrs(attrs),
         :ok <- validate_template(actor, classroom, attrs[:template_repository]),
         :ok <- validate_cutoff(attrs),
         :ok <- validate_tests(attrs),
         {:ok, slug} <- available_assignment_slug(classroom.id, attrs[:title]),
         changeset <- assignment_changeset(%Assignment{}, attrs, classroom.id, slug),
         {:ok, _assignment} <- Ecto.Changeset.apply_action(changeset, :insert),
         {:ok, assignment} <- persist_assignment(classroom, changeset, attrs) do
      broadcast({"classroom:#{classroom.id}", {:assignment_created, assignment.id}})
      {:ok, assignment}
    end
  end

  def create_assignment(_, _, _), do: {:error, :unauthorized}

  defp persist_assignment(classroom, changeset, attrs) do
    Repo.transaction(fn -> create_assignment_locked!(classroom, changeset, attrs) end)
  end

  defp create_assignment_locked!(classroom, changeset, attrs) do
    Repo.query!("SELECT id FROM classrooms WHERE id = $1 FOR UPDATE", [classroom.id])
    locked_classroom = Repo.get!(Classroom, classroom.id)

    if locked_classroom.github_connection_id != classroom.github_connection_id do
      Repo.rollback(:organization_changed)
    end

    assignment =
      changeset
      |> Ecto.Changeset.put_change(:published_at, DateTime.utc_now())
      |> Repo.insert!()

    save_tests!(assignment.id, Map.get(attrs, :tests, []))
    Repo.preload(assignment, :tests)
  end

  @doc "Updates assignment details while protecting repository topology and tests after a student accepts."
  def update_assignment(%User{} = actor, assignment_id, attrs) when is_integer(assignment_id) do
    with %Assignment{} = found <- Repo.get(Assignment, assignment_id),
         {:ok, classroom} <- Classrooms.classroom_for_teacher(actor, found.classroom_id),
         attrs <- normalize_attrs(attrs),
         attrs <- preserve_empty_existing_tests(found, attrs),
         :ok <-
           validate_template(
             actor,
             classroom,
             Map.get(attrs, :template_repository, found.template_repository)
           ),
         :ok <- validate_cutoff(attrs),
         :ok <- validate_tests_for_update(found, attrs),
         {:ok, updated} <- update_assignment_record(assignment_id, attrs) do
      broadcast({"classroom:#{updated.classroom_id}", {:assignment_updated, updated.id}})
      {:ok, updated}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def update_assignment(_, _, _), do: {:error, :unauthorized}

  defp update_assignment_record(assignment_id, attrs) do
    Repo.transaction(fn -> update_assignment_locked!(assignment_id, attrs) end)
  end

  defp update_assignment_locked!(assignment_id, attrs) do
    Repo.query!("SELECT id FROM assignments WHERE id = $1 FOR UPDATE", [assignment_id])
    assignment = Repo.get!(Assignment, assignment_id)
    accepted? = Repo.exists?(from(s in Subject, where: s.assignment_id == ^assignment_id))

    if accepted? and locked_change?(assignment, attrs), do: Repo.rollback(:assignment_locked)

    changeset = Assignment.changeset(assignment, attrs)
    if not changeset.valid?, do: Repo.rollback(changeset)

    updated = Repo.update!(changeset)
    update_tests_if_changed!(assignment, attrs)
    preload_assignment(updated)
  end

  @doc "Archives an assignment and revokes its active acceptance link without deleting repositories."
  def archive_assignment(%User{} = actor, assignment_id) do
    with %Assignment{} = assignment <- Repo.get(Assignment, assignment_id),
         {:ok, _classroom} <- Classrooms.classroom_for_teacher(actor, assignment.classroom_id) do
      result =
        Repo.transaction(fn ->
          now = DateTime.utc_now()
          Repo.update!(Ecto.Changeset.change(assignment, archived_at: now))

          from(i in Invitation,
            where: i.assignment_id == ^assignment_id and is_nil(i.revoked_at)
          )
          |> Repo.update_all(set: [revoked_at: now, updated_at: now])

          Repo.get!(Assignment, assignment_id)
        end)

      case result do
        {:ok, archived} ->
          broadcast({"classroom:#{archived.classroom_id}", {:assignment_archived, archived.id}})
          {:ok, archived}

        error ->
          error
      end
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  @doc "Deletes an assignment only before any student or team has accepted it."
  def delete_assignment(%User{} = actor, assignment_id) do
    with %Assignment{} = assignment <- Repo.get(Assignment, assignment_id),
         {:ok, _classroom} <- Classrooms.classroom_for_teacher(actor, assignment.classroom_id),
         {:ok, deleted} <- delete_assignment_record(assignment_id) do
      {:ok, deleted}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp delete_assignment_record(assignment_id) do
    Repo.transaction(fn -> delete_assignment_locked!(assignment_id) end)
  end

  defp delete_assignment_locked!(assignment_id) do
    Repo.query!("SELECT id FROM assignments WHERE id = $1 FOR UPDATE", [assignment_id])

    if Repo.exists?(from(s in Subject, where: s.assignment_id == ^assignment_id)) do
      Repo.rollback(:has_acceptances)
    end

    case Repo.get!(Assignment, assignment_id) |> Repo.delete() do
      {:ok, deleted} -> deleted
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @doc "Lists repository submissions by student or team, scoped to the assigned teachers."
  def list_submissions(%User{} = actor, assignment_id) do
    with %Assignment{} = assignment <- Repo.get(Assignment, assignment_id),
         {:ok, _classroom} <- Classrooms.classroom_for_teacher(actor, assignment.classroom_id) do
      subjects =
        from(s in Subject,
          where: s.assignment_id == ^assignment_id,
          order_by: [asc: s.accepted_at],
          preload: [:user, :repository, team: [members: :user]]
        )
        |> Repo.all()

      {:ok, subjects |> enrich_subject_profiles() |> Submissions.enrich_subjects()}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  @doc "Returns the active share link, creating one when the assignment has none."
  def create_assignment_invitation(%User{} = actor, assignment_id) do
    with :ok <- GradePush.Demo.ensure_invitations_enabled(),
         %Assignment{} = assignment <- Repo.get(Assignment, assignment_id),
         {:ok, _classroom} <- Classrooms.classroom_for_teacher(actor, assignment.classroom_id),
         true <- is_nil(assignment.archived_at) and not is_nil(assignment.published_at),
         {:ok, invitation} <- assignment_invitation_result(actor, assignment_id) do
      {:ok, invitation}
    else
      false -> {:error, :assignment_unavailable}
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp assignment_invitation_result(actor, assignment_id) do
    Repo.transaction(fn ->
      Repo.query!("SELECT id FROM assignments WHERE id = $1 FOR UPDATE", [assignment_id])
      create_or_reuse_assignment_invitation!(actor, assignment_id)
    end)
  end

  defp create_or_reuse_assignment_invitation!(actor, assignment_id) do
    case active_assignment_invitation(assignment_id) do
      %Invitation{} = invitation -> reuse_or_rotate_assignment_invitation!(actor, invitation)
      nil -> create_assignment_invitation!(actor, assignment_id)
    end
  end

  defp reuse_or_rotate_assignment_invitation!(actor, invitation) do
    if invitation_active?(invitation) do
      case decrypt_assignment_invitation_token(invitation, invitation.assignment_id) do
        {:ok, token} -> %{invitation: invitation_summary(invitation), token: token}
        {:error, reason} -> Repo.rollback(reason)
      end
    else
      Repo.update!(Ecto.Changeset.change(invitation, revoked_at: DateTime.utc_now()))
      create_assignment_invitation!(actor, invitation.assignment_id)
    end
  end

  def revoke_assignment_invitation(%User{} = actor, assignment_id) do
    with %Assignment{} = assignment <- Repo.get(Assignment, assignment_id),
         {:ok, _classroom} <- Classrooms.classroom_for_teacher(actor, assignment.classroom_id) do
      now = DateTime.utc_now()

      {count, _} =
        from(i in Invitation,
          where: i.assignment_id == ^assignment_id and is_nil(i.revoked_at)
        )
        |> Repo.update_all(set: [revoked_at: now, updated_at: now])

      if count > 0, do: broadcast({"assignment:#{assignment_id}", :invitation_revoked})
      {:ok, count}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def revoke_assignment_invitation(_, _), do: {:error, :unauthorized}

  @doc "Looks up a valid assignment invitation and safe team choices without exposing student identities."
  def assignment_invitation(token) do
    with :ok <- GradePush.Demo.ensure_invitations_enabled(),
         %Invitation{} = invitation <- valid_invitation(token),
         %Assignment{} = assignment <- assignment_for_invitation(invitation),
         true <- is_nil(assignment.archived_at),
         %Classroom{} = classroom <- Repo.get(Classroom, assignment.classroom_id) do
      {:ok,
       %{
         invitation: invitation_summary(invitation),
         assignment: assignment,
         classroom:
           Map.take(classroom, [
             :id,
             :slug,
             :title,
             :code,
             :semester,
             :academic_year
           ]),
         team_options: team_options(assignment)
       }}
    else
      false -> {:error, :invalid_invitation}
      nil -> {:error, :invalid_invitation}
      error -> error
    end
  end

  defp assignment_for_invitation(invitation) do
    case Repo.get(Assignment, invitation.assignment_id) do
      %Assignment{} = assignment -> preload_assignment(assignment)
      nil -> nil
    end
  end

  @doc "Lists available teams for a valid invitation using names and counts only."
  def list_joinable_teams(%User{} = actor, invitation_token) do
    with :ok <- GradePush.Demo.ensure_invitations_enabled(),
         true <- eligible_invitation_student?(actor),
         %Invitation{} = invitation <- valid_invitation(invitation_token),
         %Assignment{kind: "team", team_mode: "students"} = assignment <-
           Repo.get(Assignment, invitation.assignment_id),
         true <- is_nil(assignment.archived_at) and not is_nil(assignment.published_at) do
      {:ok, team_options(assignment)}
    else
      false -> {:error, :unauthorized}
      nil -> {:error, :invalid_invitation}
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_invitation}
    end
  end

  def list_joinable_teams(_, _), do: {:error, :unauthorized}

  @doc "Accepts an assignment invitation, enrolls the student in its class, and queues an idempotent repository job."
  def accept_assignment_invitation(%User{id: user_id} = actor, token, profile_attrs)
      when is_integer(user_id) and is_map(profile_attrs) do
    with :ok <- GradePush.Demo.ensure_invitations_enabled(),
         true <- eligible_invitation_student?(actor),
         %Invitation{} <- valid_invitation(token),
         {:ok, accepted} <- accept_assignment_transaction(actor, token, profile_attrs) do
      publish_assignment_acceptance(accepted, actor)
    else
      false -> {:error, :unauthorized}
      nil -> {:error, :invalid_invitation}
      error -> error
    end
  end

  def accept_assignment_invitation(_, _, _), do: {:error, :unauthorized}

  defp accept_assignment_transaction(actor, token, profile_attrs) do
    Repo.transaction(fn -> accept_assignment_locked!(actor, token, profile_attrs) end)
  end

  defp accept_assignment_locked!(actor, token, profile_attrs) do
    Repo.one!(from(u in User, where: u.id == ^actor.id, lock: "FOR UPDATE"))
    invitation = lock_assignment_invitation!(token)
    assignment = lock_published_assignment!(invitation.assignment_id)
    classroom = active_assignment_classroom!(assignment)

    ensure_student_profile!(actor, profile_attrs)
    enroll_in_classroom!(classroom.id, actor.id)
    subject = accept_subject!(actor, assignment, profile_attrs)
    repository = ensure_repository!(subject.id)
    enqueue_required_repository_jobs!(assignment, repository, subject.id)

    subject = Repo.preload(subject, [:user, :team, :repository])

    %{assignment: preload_assignment(assignment), subject: subject, repository: repository}
  end

  defp lock_assignment_invitation!(token) do
    hash = Token.digest(token)

    Repo.one(
      from(i in Invitation,
        where:
          i.token_hash == ^hash and is_nil(i.revoked_at) and
            (is_nil(i.expires_at) or i.expires_at > ^DateTime.utc_now())
      )
    ) || Repo.rollback(:invalid_invitation)
  end

  defp lock_published_assignment!(assignment_id) do
    Repo.query!("SELECT id FROM assignments WHERE id = $1 FOR UPDATE", [assignment_id])
    assignment = Repo.get!(Assignment, assignment_id)

    if assignment.archived_at || is_nil(assignment.published_at),
      do: Repo.rollback(:assignment_unavailable)

    assignment
  end

  defp active_assignment_classroom!(assignment) do
    classroom = Repo.get!(Classroom, assignment.classroom_id)
    if classroom.archived_at, do: Repo.rollback(:classroom_archived)

    unless active_classroom_connection?(classroom),
      do: Repo.rollback(:github_connection_unavailable)

    classroom
  end

  defp enqueue_required_repository_jobs!(assignment, repository, subject_id) do
    if repository.state != "ready", do: enqueue_repository_job!(subject_id)
    if assignment.kind == "team", do: enqueue_access_sync_job!(subject_id)
  end

  defp publish_assignment_acceptance(accepted, actor) do
    %{assignment: assignment, subject: subject} = accepted
    broadcast({"classroom:#{assignment.classroom_id}", {:assignment_accepted, subject.id}})
    broadcast({"assignment:#{assignment.id}", {:submission_changed, subject.id}})
    broadcast({"user:#{actor.id}", {:assignment_accepted, assignment.id}})
    {:ok, accepted}
  end

  @doc "Lists visible assignments for an actively enrolled student, with only that student's or team's work."
  def list_student_assignments(%User{id: user_id} = actor, classroom_id)
      when is_integer(user_id) and is_integer(classroom_id) do
    with true <- Accounts.student?(actor),
         true <- active_student?(classroom_id, user_id) do
      assignments =
        from(a in Assignment,
          where:
            a.classroom_id == ^classroom_id and is_nil(a.archived_at) and
              not is_nil(a.published_at),
          order_by: [asc: a.deadline_at, asc: a.title],
          preload: [:tests]
        )
        |> Repo.all()

      subjects = student_subjects(user_id, Enum.map(assignments, & &1.id))

      enriched =
        Map.new(
          subjects |> enrich_subject_profiles() |> Submissions.enrich_subjects(),
          &{&1.id, &1}
        )

      by_assignment = Map.new(subjects, &{&1.assignment_id, Map.get(enriched, &1.id)})

      {:ok,
       Enum.map(assignments, fn assignment ->
         subject = Map.get(by_assignment, assignment.id)
         student_assignment(assignment, subject)
       end)}
    else
      false -> {:error, :not_found}
      _ -> {:error, :unauthorized}
    end
  end

  def list_student_assignments(_, _), do: {:error, :unauthorized}

  @doc "Lists published assignments across active student enrollments with personal or team deadlines."
  def list_student_schedule(%User{id: user_id} = actor) when is_integer(user_id) do
    if Accounts.student?(actor) do
      assignments =
        from(a in Assignment,
          join: c in Classroom,
          on: c.id == a.classroom_id,
          join: m in ClassroomStudent,
          on: m.classroom_id == c.id and m.user_id == ^user_id,
          where:
            is_nil(m.removed_at) and is_nil(c.archived_at) and is_nil(a.archived_at) and
              not is_nil(a.published_at),
          preload: [classroom: c]
        )
        |> Repo.all()

      extensions =
        student_subject_query(user_id, Enum.map(assignments, & &1.id))
        |> select([s], {s.assignment_id, s.extension_until})
        |> Repo.all()
        |> Map.new()

      entries =
        Enum.map(assignments, fn assignment ->
          %{
            assignment: assignment,
            classroom: assignment.classroom,
            deadline_at:
              Submissions.effective_deadline(assignment.deadline_at, extensions[assignment.id])
          }
        end)

      {:ok,
       Enum.sort_by(entries, fn entry ->
         {is_nil(entry.deadline_at), entry.deadline_at && DateTime.to_unix(entry.deadline_at),
          entry.assignment.title, entry.assignment.id}
       end)}
    else
      {:error, :unauthorized}
    end
  end

  def list_student_schedule(_), do: {:error, :unauthorized}

  @doc "Fetches an assignment for an enrolled student without exposing classmates' work."
  def get_student_assignment(%User{id: user_id} = actor, classroom_id, slug)
      when is_integer(user_id) and is_integer(classroom_id) do
    with true <- Accounts.student?(actor),
         true <- active_student?(classroom_id, user_id),
         %Assignment{} = assignment <- student_visible_assignment(classroom_id, slug) do
      subject =
        student_subjects(user_id, [assignment.id])
        |> enrich_subject_profiles()
        |> Submissions.enrich_subjects()
        |> List.first()

      {:ok, student_assignment(assignment, subject)}
    else
      false -> {:error, :not_found}
      nil -> {:error, :not_found}
      _ -> {:error, :unauthorized}
    end
  end

  def get_student_assignment(_, _, _), do: {:error, :unauthorized}

  @doc "Creates a student team or a teacher-assigned team, enforcing assignment mode and capacity."
  def create_team(%User{} = actor, assignment_id, attrs) do
    with %Assignment{} = assignment <- Repo.get(Assignment, assignment_id),
         true <- assignment.kind == "team",
         :ok <- authorize_team_creation(actor, assignment),
         {:ok, name} <- team_name(attrs),
         {:ok, team} <- persist_team(actor, assignment, name) do
      broadcast({"assignment:#{assignment_id}", {:team_changed, team.id}})
      {:ok, team}
    else
      false -> {:error, :invalid_team_assignment}
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def create_team(_, _, _), do: {:error, :unauthorized}

  defp team_name(attrs) do
    name = attrs |> normalize_attrs() |> Map.get(:name, "") |> to_string() |> String.trim()
    if name == "", do: {:error, :team_name_required}, else: {:ok, name}
  end

  defp persist_team(actor, assignment, name) do
    Repo.transaction(fn ->
      Repo.query!("SELECT id FROM assignments WHERE id = $1 FOR UPDATE", [assignment.id])

      changeset =
        %Team{assignment_id: assignment.id, created_by_id: actor.id}
        |> Team.changeset(%{name: name, join_code: join_code()})

      team = insert_team!(changeset)

      if Accounts.student?(actor) do
        insert_team_member!(assignment, team, actor.id)
      end

      Repo.preload(team, members: :user)
    end)
  end

  defp insert_team!(changeset) do
    case Repo.insert(changeset) do
      {:ok, team} -> team
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @doc "Joins a team in a student-formed assignment without exceeding its configured size."
  def join_team(%User{} = actor, assignment_id, team_id) do
    with :ok <- GradePush.Demo.ensure_invitations_enabled(),
         true <- Accounts.student?(actor),
         %Assignment{kind: "team", team_mode: "students"} = assignment <-
           Repo.get(Assignment, assignment_id),
         true <- active_student?(assignment.classroom_id, actor.id),
         %Team{} = team <- active_team(team_id, assignment_id),
         {:ok, updated} <- update_team_membership(assignment, team, actor.id) do
      broadcast({"assignment:#{assignment_id}", {:team_changed, team.id}})
      {:ok, updated}
    else
      false -> {:error, :unauthorized}
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_team}
    end
  end

  def join_team(_, _, _), do: {:error, :unauthorized}

  @doc "Assigns a rostered student to a teacher-managed team."
  def add_team_member(%User{} = actor, assignment_id, team_id, student_user_id) do
    with %Assignment{kind: "team", team_mode: "teacher"} = assignment <-
           Repo.get(Assignment, assignment_id),
         {:ok, _classroom} <- Classrooms.classroom_for_teacher(actor, assignment.classroom_id),
         true <- active_student?(assignment.classroom_id, student_user_id),
         %Team{} = team <- active_team(team_id, assignment_id),
         {:ok, updated} <- update_team_membership(assignment, team, student_user_id) do
      broadcast({"assignment:#{assignment_id}", {:team_changed, team.id}})
      {:ok, updated}
    else
      nil -> {:error, :not_found}
      false -> {:error, :student_not_enrolled}
      error -> error
    end
  end

  def add_team_member(_, _, _, _), do: {:error, :unauthorized}

  defp update_team_membership(assignment, team, user_id) do
    with {:ok, updated} <- persist_team_membership(assignment, team, user_id),
         :ok <- queue_existing_subject(assignment.id, team.id) do
      {:ok, updated}
    end
  end

  defp persist_team_membership(assignment, team, user_id) do
    Repo.transaction(fn ->
      Repo.query!("SELECT id FROM assignments WHERE id = $1 FOR UPDATE", [assignment.id])
      insert_team_member!(assignment, team, user_id)
      Repo.preload(team, members: :user)
    end)
  end

  @doc "Lists teams and their declared students for a classroom teacher."
  def list_teams(%User{} = actor, assignment_id) when is_integer(assignment_id) do
    with %Assignment{kind: "team"} = assignment <- Repo.get(Assignment, assignment_id),
         {:ok, _classroom} <- Classrooms.classroom_for_teacher(actor, assignment.classroom_id) do
      teams =
        from(team in Team,
          where: team.assignment_id == ^assignment_id and is_nil(team.archived_at),
          order_by: [asc: team.inserted_at, asc: team.id],
          preload: [members: :user]
        )
        |> Repo.all()
        |> Enum.map(fn team ->
          %{team | members: Enum.filter(team.members, &is_nil(&1.left_at))}
        end)

      users =
        teams
        |> Enum.flat_map(& &1.members)
        |> Enum.map(& &1.user)
        |> Accounts.with_student_profiles()
        |> Map.new(&{&1.id, &1})

      {:ok,
       Enum.map(teams, fn team ->
         members = Enum.map(team.members, &%{&1 | user: Map.get(users, &1.user_id)})
         %{team | members: members}
       end)}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def list_teams(_, _), do: {:error, :unauthorized}

  @doc "Returns the persisted repository creation intent for a trusted background worker."
  def provisioning_intent(subject_id) when is_integer(subject_id) do
    with %Subject{} = subject <- Repo.get(Subject, subject_id),
         %Assignment{} = assignment <-
           Repo.get(Assignment, subject.assignment_id) |> preload_assignment(),
         %Classroom{} = classroom <- Repo.get(Classroom, assignment.classroom_id),
         {:ok, connection} <- Classrooms.classroom_github_connection(classroom),
         %Repository{} = repository <- Repo.get_by(Repository, subject_id: subject.id) do
      members = subject_recipients(subject)

      if members == [] do
        {:error, :no_github_recipients}
      else
        {:ok,
         %{
           subject_id: subject.id,
           assignment_id: assignment.id,
           connection_id: connection.id,
           installation_id: connection.installation_id,
           organization_id: connection.github_organization_id,
           organization_login: connection.login,
           repository_id: repository.github_repository_id,
           repository: %{
             github_repository_id: repository.github_repository_id,
             owner_login: repository.owner_login,
             name: repository.name,
             full_name: repository.full_name,
             html_url: repository.html_url,
             state: repository.state
           },
           repository_name: repository_name(assignment, classroom, subject),
           visibility: assignment.repository_visibility,
           template_owner: template_part(assignment.template_repository, 0),
           template_name: template_part(assignment.template_repository, 1),
           description: assignment.title,
           workflow_config: workflow_config(assignment),
           autograding_enabled: assignment.autograding_enabled,
           workflow_id: repository.workflow_id,
           workflow_path: repository.workflow_path,
           workflow_file_sha: repository.workflow_file_sha,
           github_repository_id: repository.github_repository_id,
           owner_login: repository.owner_login,
           name: repository.name,
           full_name: repository.full_name,
           html_url: repository.html_url,
           recipients: members
         }}
      end
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
      _ -> {:error, :incomplete_provisioning_intent}
    end
  end

  @doc "Persists a repository ID immediately after GitHub creates it, without adopting name collisions."
  def repository_created(subject_id, attrs) when is_integer(subject_id) and is_map(attrs) do
    case Repo.get_by(Repository, subject_id: subject_id) do
      %Repository{} = repository ->
        attrs = normalize_attrs(attrs)
        github_repository_id = Map.get(attrs, :github_repository_id)

        cond do
          repository.github_repository_id == github_repository_id and
              not is_nil(github_repository_id) ->
            {:ok, repository}

          not is_nil(repository.github_repository_id) ->
            {:error, :repository_identity_conflict}

          true ->
            repository
            |> Repository.changeset(Map.merge(attrs, %{state: "pending"}))
            |> Repo.update()
            |> publish_repository_change(subject_id)
        end

      nil ->
        {:error, :not_found}
    end
  end

  @doc "Marks a repository ready once GitHub creation, workflow setup, and collaborator setup finish."
  def repository_provisioned(subject_id, attrs) when is_integer(subject_id) and is_map(attrs) do
    case Repo.get_by(Repository, subject_id: subject_id) do
      %Repository{} = repository ->
        attrs = normalize_attrs(attrs)
        incoming_id = attrs[:github_repository_id]

        cond do
          not is_nil(repository.github_repository_id) and
              repository.github_repository_id != incoming_id ->
            {:error, :repository_identity_conflict}

          repository.state == "ready" and repository.github_repository_id == incoming_id ->
            {:ok, repository}

          true ->
            repository
            |> Repository.changeset(Map.merge(attrs, %{state: "ready", last_error: nil}))
            |> Repo.update()
            |> publish_repository_change(subject_id)
        end

      nil ->
        {:error, :not_found}
    end
  end

  @doc "Records only a sanitized provisioning failure code for a teacher-visible retry."
  def repository_provisioning_failed(subject_id, error_code) when is_integer(subject_id) do
    allowed_codes =
      ~w(github_unavailable permission_denied repository_conflict workflow_setup_failed collaborator_setup_failed)

    safe_code = if error_code in allowed_codes, do: error_code, else: "github_unavailable"

    case Repo.get_by(Repository, subject_id: subject_id) do
      nil ->
        {:error, :not_found}

      repository ->
        repository
        |> Repository.changeset(%{state: "failed", last_error: safe_code})
        |> Repo.update()
        |> publish_repository_change(subject_id)
    end
  end

  @doc "Retries failed repository provisioning for a teacher assigned to the classroom."
  def retry_repository(%User{} = actor, subject_id) when is_integer(subject_id) do
    with %Subject{} = subject <- Repo.get(Subject, subject_id),
         {:ok, _classroom} <-
           Classrooms.classroom_for_teacher(
             actor,
             Repo.get!(Assignment, subject.assignment_id).classroom_id
           ),
         %Repository{} = repository <- Repo.get_by(Repository, subject_id: subject_id),
         true <- repository.state in ["failed", "pending"] do
      result =
        Repo.transaction(fn ->
          repository
          |> Repository.changeset(%{state: "pending", last_error: nil})
          |> Repo.update!()

          enqueue_repository_job!(subject_id)
          Repo.get_by!(Repository, subject_id: subject_id)
        end)

      case result do
        {:ok, updated} -> {:ok, updated}
        error -> error
      end
    else
      false -> {:error, :repository_ready}
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def retry_repository(_, _), do: {:error, :unauthorized}

  defp publish_repository_change({:ok, repository}, subject_id) do
    assignment_id =
      from(subject in Subject,
        where: subject.id == ^subject_id,
        select: subject.assignment_id
      )
      |> Repo.one()

    if assignment_id do
      broadcast({"assignment:#{assignment_id}", {:repository_changed, subject_id}})
      broadcast({"submission:#{subject_id}", {:repository_changed, subject_id}})
    end

    {:ok, repository}
  end

  defp publish_repository_change(error, _), do: error

  defp preload_assignment(assignment), do: Repo.preload(assignment, :tests)

  defp active_classroom_connection(actor, classroom) do
    case Classrooms.get_github_connection(actor, classroom.github_connection_id) do
      {:ok, %GitHubConnection{status: "active"} = connection} -> {:ok, connection}
      _ -> {:error, :github_connection_unavailable}
    end
  end

  defp active_classroom_connection?(classroom) do
    case Repo.get(GitHubConnection, classroom.github_connection_id) do
      %GitHubConnection{status: "active"} -> true
      _ -> false
    end
  end

  defp normalize_attrs(attrs) do
    attrs = Map.new(attrs, fn {key, value} -> {normalize_key(key), value} end)
    attrs = rename_key(attrs, :deadline, :deadline_at)
    attrs = rename_key(attrs, :cutoff, :cutoff_enabled)
    attrs = rename_key(attrs, :template, :template_repository)
    attrs = rename_key(attrs, :autograding, :autograding_enabled)

    attrs
    |> normalize_present(:title, &localized_value/1)
    |> normalize_present(:instructions, &empty_to_string/1)
    |> normalize_present(:template_repository, &empty_to_nil/1)
    |> normalize_present(:tests, &normalize_tests/1)
    |> normalize_present(:name, &localized_value/1)
    |> normalize_present(:description, &empty_to_string/1)
  end

  defp assignment_changeset(assignment, attrs, classroom_id, slug) do
    assignment
    |> Assignment.changeset(attrs)
    |> Ecto.Changeset.put_change(:classroom_id, classroom_id)
    |> Ecto.Changeset.put_change(:slug, slug)
  end

  defp validate_tests(attrs) do
    tests = Map.get(attrs, :tests, [])

    if autograding_enabled?(attrs, false) and tests == [],
      do: {:error, :tests_required},
      else: validate_test_changesets(tests)
  end

  defp validate_tests_for_update(assignment, attrs) do
    tests = Map.get(attrs, :tests)

    configured_tests =
      tests || Repo.all(from(t in AssignmentTest, where: t.assignment_id == ^assignment.id))

    if autograding_enabled?(attrs, assignment.autograding_enabled) and
         configured_tests == [],
       do: {:error, :tests_required},
       else: if(tests, do: validate_test_changesets(tests), else: :ok)
  end

  defp autograding_enabled?(attrs, default),
    do: Ecto.Type.cast(:boolean, Map.get(attrs, :autograding_enabled, default)) == {:ok, true}

  defp preserve_empty_existing_tests(
         %Assignment{autograding_enabled: true},
         %{autograding_enabled: true, tests: []} = attrs
       ),
       do: Map.delete(attrs, :tests)

  defp preserve_empty_existing_tests(
         %Assignment{autograding_enabled: true},
         %{tests: []} = attrs
       ) do
    if Map.has_key?(attrs, :autograding_enabled), do: attrs, else: Map.delete(attrs, :tests)
  end

  defp preserve_empty_existing_tests(_assignment, attrs), do: attrs

  defp validate_test_changesets(tests) do
    changesets = Enum.map(tests, &AssignmentTest.changeset(%AssignmentTest{}, &1))

    case Enum.find(changesets, &(not &1.valid?)) do
      nil -> :ok
      changeset -> {:error, changeset}
    end
  end

  defp save_tests!(_assignment_id, []), do: :ok

  defp save_tests!(assignment_id, tests) do
    Enum.each(tests, fn attrs ->
      %AssignmentTest{assignment_id: assignment_id}
      |> AssignmentTest.changeset(attrs)
      |> Repo.insert!()
    end)
  end

  defp validate_cutoff(attrs) do
    if Map.get(attrs, :cutoff_enabled, false),
      do: {:error, :cutoff_unavailable},
      else: :ok
  end

  defp validate_template(actor, classroom, value) when value in [nil, ""] do
    with {:ok, _connection} <- active_classroom_connection(actor, classroom), do: :ok
  end

  defp validate_template(actor, classroom, template),
    do: Classrooms.template_repository_available?(actor, classroom.id, template)

  defp locked_change?(assignment, attrs) do
    scalar_change? =
      Enum.any?(Enum.reject(@locked_after_acceptance, &(&1 == "tests")), fn string_key ->
        key = String.to_existing_atom(string_key)
        Map.has_key?(attrs, key) and Map.get(attrs, key) != Map.get(assignment, key)
      end)

    scalar_change? or
      (Map.has_key?(attrs, :tests) and test_configuration_changed?(assignment.id, attrs.tests))
  end

  defp test_configuration_changed?(assignment_id, requested_tests) do
    fields = [
      :name,
      :description,
      :type,
      :points,
      :timeout_seconds,
      :command,
      :path,
      :input,
      :expected
    ]

    requested =
      Enum.map(requested_tests, fn test_attrs ->
        test_attrs
        |> then(&AssignmentTest.changeset(%AssignmentTest{}, &1))
        |> Ecto.Changeset.apply_changes()
        |> Map.take(fields)
      end)

    persisted =
      from(test in AssignmentTest,
        where: test.assignment_id == ^assignment_id,
        order_by: [asc: test.id]
      )
      |> Repo.all()
      |> Enum.map(&Map.take(&1, fields))

    requested != persisted
  end

  defp update_tests_if_changed!(assignment, attrs) do
    if Map.has_key?(attrs, :tests) and test_configuration_changed?(assignment.id, attrs.tests) do
      Repo.delete_all(from(test in AssignmentTest, where: test.assignment_id == ^assignment.id))
      save_tests!(assignment.id, attrs.tests)
    end
  end

  defp available_assignment_slug(classroom_id, title) do
    base = slugify(title || "assignment")
    base = if base == "", do: "assignment", else: base
    suffix = Base.url_encode64(:crypto.strong_rand_bytes(3), padding: false) |> String.downcase()
    slug = "#{String.slice(base, 0, 68)}-#{suffix}"

    if Repo.exists?(
         from(a in Assignment, where: a.classroom_id == ^classroom_id and a.slug == ^slug)
       ),
       do: {:error, :slug_conflict},
       else: {:ok, slug}
  end

  defp subject_counts([]), do: %{}

  defp subject_counts(assignment_ids) do
    from(s in Subject,
      where: s.assignment_id in ^assignment_ids,
      group_by: s.assignment_id,
      select: {s.assignment_id, count(s.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp valid_invitation(token) do
    hash = Token.digest(token)
    now = DateTime.utc_now()

    Repo.one(
      from(i in Invitation,
        where:
          i.token_hash == ^hash and is_nil(i.revoked_at) and
            (is_nil(i.expires_at) or i.expires_at > ^now)
      )
    )
  end

  defp active_assignment_invitation(assignment_id) do
    Repo.one(
      from(i in Invitation,
        where: i.assignment_id == ^assignment_id and is_nil(i.revoked_at),
        lock: "FOR UPDATE",
        limit: 1
      )
    )
  end

  defp create_assignment_invitation!(actor, assignment_id) do
    {token, token_hash} = Token.generate()

    case Crypto.encrypt(token, assignment_invitation_purpose(assignment_id)) do
      {:ok, token_encrypted} ->
        invitation =
          %Invitation{assignment_id: assignment_id, created_by_id: actor.id}
          |> Invitation.changeset(%{token_hash: token_hash, token_encrypted: token_encrypted})
          |> Repo.insert!()

        %{invitation: invitation_summary(invitation), token: token}

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp decrypt_assignment_invitation_token(invitation, assignment_id) do
    Crypto.decrypt(invitation.token_encrypted, assignment_invitation_purpose(assignment_id))
  end

  defp assignment_invitation_purpose(assignment_id), do: "assignment-invitation:#{assignment_id}"

  defp invitation_summary(invitation), do: Map.take(invitation, [:id, :expires_at, :revoked_at])

  defp invitation_active?(%Invitation{expires_at: nil}), do: true

  defp invitation_active?(%Invitation{expires_at: expires_at}),
    do: DateTime.compare(expires_at, DateTime.utc_now()) == :gt

  defp eligible_invitation_student?(%User{} = actor),
    do: not Accounts.teacher?(actor) and not Accounts.admin?(actor)

  defp team_options(%Assignment{} = assignment) do
    from(team in Team,
      left_join: member in TeamMember,
      on: member.team_id == team.id and is_nil(member.left_at),
      where: team.assignment_id == ^assignment.id and is_nil(team.archived_at),
      group_by: [team.id, team.name],
      order_by: [asc: team.name],
      select: %{id: team.id, name: team.name, member_count: count(member.id)}
    )
    |> Repo.all()
    |> Enum.filter(&(&1.member_count < assignment.team_size))
    |> Enum.map(&Map.put(&1, :team_size, assignment.team_size))
  end

  defp student_visible_assignment(classroom_id, slug) do
    from(a in Assignment,
      where:
        a.classroom_id == ^classroom_id and a.slug == ^slug and is_nil(a.archived_at) and
          not is_nil(a.published_at),
      preload: [:tests]
    )
    |> Repo.one()
  end

  defp student_subjects(_user_id, []), do: []

  defp student_subjects(user_id, assignment_ids) do
    student_subject_query(user_id, assignment_ids)
    |> preload([:user, :repository, team: [members: :user]])
    |> Repo.all()
  end

  defp student_subject_query(user_id, assignment_ids) do
    team_ids =
      from(m in TeamMember,
        where: m.user_id == ^user_id and is_nil(m.left_at),
        select: m.team_id
      )

    from(s in Subject,
      where:
        s.assignment_id in ^assignment_ids and
          (s.user_id == ^user_id or s.team_id in subquery(team_ids))
    )
  end

  defp enrich_subject_profiles(subjects) do
    users =
      subjects
      |> Enum.flat_map(fn subject ->
        [subject.user | Enum.map((subject.team && subject.team.members) || [], & &1.user)]
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(& &1.id)

    users_by_id = Map.new(Accounts.with_student_profiles(users), &{&1.id, &1})

    Enum.map(subjects, fn subject ->
      team =
        case subject.team do
          nil ->
            nil

          team ->
            %{
              team
              | members: Enum.map(team.members, &%{&1 | user: Map.get(users_by_id, &1.user_id)})
            }
        end

      %{subject | user: Map.get(users_by_id, subject.user_id), team: team}
    end)
  end

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: value

  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _ -> nil
    end
  end

  defp parse_positive_integer(_), do: nil

  defp ensure_student_profile!(actor, attrs) do
    case Accounts.student_profile(actor) do
      %{name: name, student_id: student_id} when is_binary(name) and is_binary(student_id) ->
        :ok

      _ ->
        case Accounts.enroll_student(actor, attrs) do
          {:ok, _membership} -> :ok
          {:error, reason} -> Repo.rollback(reason)
        end
    end
  end

  defp student_assignment(assignment, nil) do
    %{assignment: assignment, subject: nil, repository: nil, latest_push: nil, latest_grade: nil}
  end

  defp student_assignment(assignment, subject) do
    %{
      assignment: assignment,
      subject: subject,
      repository: subject.repository,
      latest_push: subject.latest_push,
      latest_grade: subject.latest_grade
    }
  end

  defp active_student?(classroom_id, user_id) do
    Repo.exists?(
      from(m in ClassroomStudent,
        where: m.classroom_id == ^classroom_id and m.user_id == ^user_id and is_nil(m.removed_at)
      )
    )
  end

  defp active_team(team_id, assignment_id) do
    Repo.one(
      from(team in Team,
        where:
          team.id == ^team_id and team.assignment_id == ^assignment_id and
            is_nil(team.archived_at)
      )
    )
  end

  defp enroll_in_classroom!(classroom_id, user_id) do
    member = Repo.get_by(ClassroomStudent, classroom_id: classroom_id, user_id: user_id)
    member = member || %ClassroomStudent{classroom_id: classroom_id, user_id: user_id}

    member
    |> Ecto.Changeset.change(joined_at: member.joined_at || DateTime.utc_now(), removed_at: nil)
    |> Repo.insert_or_update!()
  end

  defp accept_subject!(actor, %Assignment{kind: "individual"} = assignment, _profile_attrs) do
    subject =
      Repo.get_by(Subject, assignment_id: assignment.id, user_id: actor.id) ||
        %Subject{assignment_id: assignment.id, user_id: actor.id}
        |> Subject.changeset(%{
          kind: "individual",
          accepted_at: DateTime.utc_now(),
          user_id: actor.id
        })
        |> Repo.insert!()

    ensure_repository!(subject.id)
    subject
  end

  defp accept_subject!(
         actor,
         %Assignment{kind: "team", team_mode: "students"} = assignment,
         attrs
       ) do
    team = student_formed_team!(actor, assignment, attrs)
    insert_team_member!(assignment, team, actor.id)
    team_subject!(assignment, team)
  end

  defp accept_subject!(actor, %Assignment{kind: "team", team_mode: "teacher"} = assignment, attrs) do
    team = teacher_assigned_team!(actor, assignment, attrs)
    ensure_assigned_team_member!(actor, assignment, team)
    team_subject!(assignment, team)
  end

  defp student_formed_team!(actor, assignment, attrs) do
    team_id = value(attrs, :team_id) |> parse_positive_integer()
    team_name = value(attrs, :team_name) |> empty_to_nil()
    membership = current_team_membership(assignment.id, actor.id)

    case {team_id, membership, team_name} do
      {id, %TeamMember{team_id: existing_id}, _} when is_integer(id) and existing_id != id ->
        Repo.rollback(:already_in_team)

      {id, _, _} when is_integer(id) ->
        active_team(id, assignment.id) || Repo.rollback(:invalid_team)

      {_, %TeamMember{team_id: existing_id}, _} ->
        Repo.get!(Team, existing_id)

      {_, _, name} when is_binary(name) ->
        create_student_team!(actor, assignment, name)

      _ ->
        Repo.rollback(:team_required)
    end
  end

  defp current_team_membership(assignment_id, user_id) do
    Repo.one(
      from(member in TeamMember,
        where:
          member.assignment_id == ^assignment_id and member.user_id == ^user_id and
            is_nil(member.left_at)
      )
    )
  end

  defp create_student_team!(actor, assignment, name) do
    %Team{assignment_id: assignment.id, created_by_id: actor.id}
    |> Team.changeset(%{name: name, join_code: join_code()})
    |> insert_team!()
  end

  defp teacher_assigned_team!(actor, assignment, attrs) do
    team_id = value(attrs, :team_id) |> parse_positive_integer()

    if is_integer(team_id),
      do: active_team(team_id, assignment.id) || Repo.rollback(:invalid_team),
      else: assigned_team_for(actor, assignment)
  end

  defp assigned_team_for(actor, assignment) do
    Repo.one(
      from(team in Team,
        join: member in TeamMember,
        on: member.team_id == team.id,
        where:
          team.assignment_id == ^assignment.id and member.assignment_id == ^assignment.id and
            member.user_id == ^actor.id and is_nil(team.archived_at) and is_nil(member.left_at)
      )
    ) || Repo.rollback(:invalid_team)
  end

  defp ensure_assigned_team_member!(actor, assignment, team) do
    assigned? =
      Repo.exists?(
        from(m in TeamMember,
          where:
            m.assignment_id == ^assignment.id and m.team_id == ^team.id and
              m.user_id == ^actor.id and is_nil(m.left_at)
        )
      )

    unless assigned?, do: Repo.rollback(:team_assignment_required)
  end

  defp team_subject!(assignment, team) do
    Repo.get_by(Subject, assignment_id: assignment.id, team_id: team.id) ||
      %Subject{assignment_id: assignment.id, team_id: team.id}
      |> Subject.changeset(%{kind: "team", accepted_at: DateTime.utc_now(), team_id: team.id})
      |> Repo.insert!()
  end

  defp ensure_repository!(subject_id) do
    Repo.get_by(Repository, subject_id: subject_id) ||
      %Repository{subject_id: subject_id}
      |> Repository.changeset(%{state: "pending", subject_id: subject_id})
      |> Repo.insert!()
  end

  defp enqueue_repository_job!(subject_id) do
    job =
      ProvisionAssignmentRepository.new(
        %{"subject_id" => subject_id},
        unique: [
          fields: [:worker, :args],
          keys: [:subject_id],
          period: 300,
          states: [:available, :scheduled, :executing, :retryable]
        ]
      )

    case Oban.insert(job) do
      {:ok, _job} -> :ok
      {:error, reason} -> Repo.rollback({:job_enqueue_failed, reason})
    end
  end

  defp queue_existing_subject(assignment_id, team_id) do
    case Repo.get_by(Subject, assignment_id: assignment_id, team_id: team_id) do
      %Subject{id: subject_id} ->
        enqueue_access_sync_job(subject_id)

      nil ->
        :ok
    end
  end

  defp enqueue_access_sync_job(subject_id) do
    case Repo.transaction(fn -> enqueue_access_sync_job!(subject_id) end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp enqueue_access_sync_job!(subject_id) do
    job =
      SyncAssignmentRepositoryAccess.new(
        %{"subject_id" => subject_id},
        unique: [
          fields: [:worker, :args],
          keys: [:subject_id],
          period: 300,
          states: [:available, :scheduled, :retryable]
        ]
      )

    case Oban.insert(job) do
      {:ok, _job} -> :ok
      {:error, reason} -> Repo.rollback({:job_enqueue_failed, reason})
    end
  end

  defp insert_team_member!(assignment, team, user_id) do
    Repo.query!("SELECT id FROM assignment_teams WHERE id = $1 FOR UPDATE", [team.id])

    count =
      Repo.aggregate(
        from(m in TeamMember, where: m.team_id == ^team.id and is_nil(m.left_at)),
        :count
      )

    existing =
      Repo.get_by(TeamMember,
        assignment_id: assignment.id,
        team_id: team.id,
        user_id: user_id
      )

    cond do
      existing && is_nil(existing.left_at) ->
        existing

      count >= assignment.team_size ->
        Repo.rollback(:team_full)

      existing ->
        existing
        |> Ecto.Changeset.change(left_at: nil)
        |> Repo.update!()

      true ->
        %TeamMember{assignment_id: assignment.id, team_id: team.id, user_id: user_id}
        |> Ecto.Changeset.change()
        |> Repo.insert!()
    end
  end

  defp authorize_team_creation(actor, %Assignment{} = assignment) do
    cond do
      Accounts.teacher?(actor) or Accounts.admin?(actor) ->
        case Classrooms.classroom_for_teacher(actor, assignment.classroom_id) do
          {:ok, _} -> :ok
          error -> error
        end

      Accounts.student?(actor) and assignment.team_mode == "students" and
          active_student?(assignment.classroom_id, actor.id) ->
        :ok

      true ->
        {:error, :unauthorized}
    end
  end

  defp subject_recipients(%Subject{kind: "individual", user_id: user_id}) do
    from(user in User,
      join: membership in GradePush.Accounts.InstitutionMembership,
      on: membership.user_id == user.id,
      where: user.id == ^user_id and membership.role == :student,
      select: %{github_id: user.github_id, login: user.login}
    )
    |> Repo.one()
    |> case do
      %{github_id: id, login: login} when is_integer(id) and is_binary(login) ->
        [%{github_id: id, login: login}]

      _ ->
        []
    end
  end

  defp subject_recipients(%Subject{kind: "team", team_id: team_id}) do
    from(member in TeamMember,
      join: user in User,
      on: user.id == member.user_id,
      join: membership in GradePush.Accounts.InstitutionMembership,
      on: membership.user_id == user.id and membership.role == :student,
      where: member.team_id == ^team_id and is_nil(member.left_at),
      order_by: [asc: member.inserted_at],
      select: %{github_id: user.github_id, login: user.login}
    )
    |> Repo.all()
    |> Enum.filter(&(is_integer(&1.github_id) and is_binary(&1.login)))
  end

  defp workflow_config(%Assignment{autograding_enabled: false}), do: nil

  defp workflow_config(%Assignment{} = assignment) do
    assignment.tests
    |> Enum.map(fn test ->
      %{
        id: test.id,
        name: test.name,
        description: test.description,
        type: test.type,
        command: test.command,
        path: test.path,
        input: test.input,
        expected: test.expected,
        points: test.points,
        timeout_seconds: test.timeout_seconds
      }
    end)
  end

  defp repository_name(assignment, classroom, subject) do
    identifier =
      case subject.kind do
        "individual" ->
          case Accounts.get_user(subject.user_id) do
            %User{student_id: student_id} when is_binary(student_id) and student_id != "" ->
              student_id

            %User{login: login} ->
              login

            _ ->
              "student"
          end

        "team" ->
          case Repo.get(Team, subject.team_id) do
            %Team{name: name} -> name
            _ -> "team"
          end
      end

    assignment.repository_name_pattern
    |> String.replace("{classroom}", slugify(classroom.code))
    |> String.replace("{assignment}", slugify(assignment.slug))
    |> String.replace("{identifier}", slugify(identifier))
    |> String.replace("{team}", slugify(identifier))
    |> slugify()
    |> String.slice(0, 100)
  end

  defp template_part(nil, _index), do: nil
  defp template_part("", _index), do: nil

  defp template_part(template, index),
    do: template |> String.split("/", parts: 2) |> Enum.at(index)

  defp join_code,
    do: :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false) |> String.upcase()

  defp normalize_tests(tests) when is_list(tests), do: Enum.map(tests, &normalize_attrs/1)
  defp normalize_tests(_), do: []

  defp rename_key(map, key, key), do: map

  defp rename_key(map, from, to) do
    case Map.pop(map, from) do
      {nil, _} -> map
      {value, rest} -> Map.put_new(rest, to, value)
    end
  end

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key), do: Map.get(@normalized_keys, key, key)

  defp localized_value(value) when is_binary(value), do: String.trim(value)

  defp localized_value(value) when is_map(value) do
    value |> Map.values() |> Enum.find(&is_binary/1) |> empty_to_string()
  end

  defp localized_value(_), do: ""
  defp empty_to_string(value) when is_binary(value), do: String.trim(value)
  defp empty_to_string(_), do: ""
  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil

  defp empty_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp empty_to_nil(value), do: value

  defp normalize_present(attrs, key, fun) do
    if Map.has_key?(attrs, key), do: Map.update!(attrs, key, fun), else: attrs
  end

  defp value(attrs, key) do
    case Map.get(attrs, key) do
      nil -> Map.get(attrs, Atom.to_string(key))
      value -> value
    end
  end

  defp slugify(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/[\x{0300}-\x{036f}]/u, "")
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp broadcast({topic, message}), do: Phoenix.PubSub.broadcast(GradePush.PubSub, topic, message)
end
