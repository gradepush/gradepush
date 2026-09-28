defmodule GradePush.Classrooms do
  @moduledoc "Classroom access, rosters, teacher collaboration, and GitHub organization sharing."

  import Ecto.Query

  alias Ecto.Multi
  alias GradePush.Accounts
  alias GradePush.Accounts.InstitutionMembership
  alias GradePush.Accounts.User
  alias GradePush.Assignments.Assignment
  alias GradePush.Crypto

  alias GradePush.Classrooms.{
    Classroom,
    ClassroomStudent,
    ClassroomTeacher,
    GitHubConnection,
    GitHubConnectionTeacher,
    Invitation
  }

  alias GradePush.Repo
  alias GradePush.Teaching.Token

  @doc "Lists only classrooms the actor teaches. Institution administrators receive no implicit content access."
  def list_classrooms(actor, opts \\ [])

  def list_classrooms(%User{id: user_id} = actor, opts) when is_integer(user_id) do
    if instructional_member?(actor) do
      include_archived? = Keyword.get(opts, :include_archived, false)

      classrooms =
        from(c in Classroom,
          join: t in ClassroomTeacher,
          on: t.classroom_id == c.id and t.user_id == ^user_id,
          where: ^include_archived? or is_nil(c.archived_at),
          order_by: [asc: c.title]
        )
        |> Repo.all()

      {:ok, hydrate_classrooms(classrooms)}
    else
      {:error, :unauthorized}
    end
  end

  def list_classrooms(_, _), do: {:error, :unauthorized}

  @doc "Lists classroom metadata for institution administrators without exposing student identities or assignment content."
  def list_admin_classrooms(%User{} = actor) do
    if Accounts.admin?(actor) do
      classrooms =
        from(c in Classroom, where: is_nil(c.archived_at), order_by: [asc: c.title])
        |> Repo.all()

      {:ok, Enum.map(hydrate_classrooms(classrooms), &admin_metadata/1)}
    else
      {:error, :unauthorized}
    end
  end

  def list_admin_classrooms(_), do: {:error, :unauthorized}

  @doc "Fetches a classroom only when the actor is one of its collaborating teachers."
  def get_classroom(%User{id: user_id} = actor, slug) when is_integer(user_id) do
    with true <- instructional_member?(actor),
         %Classroom{} = classroom <- Repo.get_by(Classroom, slug: slug),
         true <- classroom_teacher?(user_id, classroom.id) do
      {:ok, classroom |> hydrate_classroom()}
    else
      _ -> {:error, :not_found}
    end
  end

  def get_classroom(_, _), do: {:error, :not_found}

  def classroom_for_teacher(%User{} = actor, classroom_id) when is_integer(classroom_id) do
    with :ok <- require_classroom_teacher(actor, classroom_id),
         %Classroom{} = classroom <- Repo.get(Classroom, classroom_id) do
      {:ok, hydrate_classroom(classroom)}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def classroom_for_teacher(_, _), do: {:error, :unauthorized}

  def institution_teacher?(user_id), do: eligible_teacher?(user_id)

  @doc "Creates a classroom and makes its creator an equal classroom teacher."
  def create_classroom(%User{id: user_id} = actor, attrs) when is_integer(user_id) do
    if instructional_member?(actor) do
      attrs = normalize_classroom_attrs(attrs, actor) |> Map.drop([:slug])

      with :ok <- validate_connection_access(actor, attrs[:github_connection_id]),
           {:ok, slug} <- available_classroom_slug(attrs),
           {:ok, classroom} <- persist_classroom(attrs, slug, user_id) do
        broadcast({"user:#{user_id}", {:classroom_created, classroom.id}})
        {:ok, hydrate_classroom(classroom)}
      end
    else
      {:error, :unauthorized}
    end
  end

  def create_classroom(_, _), do: {:error, :unauthorized}

  defp persist_classroom(attrs, slug, user_id) do
    Multi.new()
    |> Multi.insert(:classroom, fn _ ->
      %Classroom{}
      |> Classroom.changeset(Map.put(attrs, :slug, slug))
      |> Ecto.Changeset.put_change(:created_by_id, user_id)
    end)
    |> Multi.insert(:teacher, fn %{classroom: classroom} ->
      %ClassroomTeacher{classroom_id: classroom.id, user_id: user_id}
      |> Ecto.Changeset.change()
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{classroom: classroom}} -> {:ok, classroom}
      {:error, _step, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc "Updates classroom details without changing its collaborating teachers."
  def update_classroom(%User{id: user_id} = actor, classroom_id, attrs)
      when is_integer(user_id) and is_integer(classroom_id) do
    with :ok <- require_classroom_teacher(actor, classroom_id),
         %Classroom{} <- Repo.get(Classroom, classroom_id) do
      attrs = normalize_classroom_attrs(attrs, actor)

      with {:ok, updated} <- update_classroom_record(actor, classroom_id, attrs) do
        broadcast({"classroom:#{updated.id}", {:classroom_updated, updated.id}})
        {:ok, hydrate_classroom(updated)}
      end
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def update_classroom(_, _, _), do: {:error, :unauthorized}

  defp update_classroom_record(actor, classroom_id, attrs) do
    case Repo.transaction(fn -> update_classroom_locked!(actor, classroom_id, attrs) end) do
      {:ok, updated} -> {:ok, updated}
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_classroom_locked!(actor, classroom_id, attrs) do
    Repo.query!("SELECT id FROM classrooms WHERE id = $1 FOR UPDATE", [classroom_id])
    classroom = Repo.get!(Classroom, classroom_id)
    connection_id = Map.get(attrs, :github_connection_id, classroom.github_connection_id)

    ensure_connection_change_allowed!(classroom, connection_id)
    validate_connection_access!(actor, connection_id)

    case Repo.update(Classroom.changeset(classroom, attrs)) do
      {:ok, updated} -> updated
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp ensure_connection_change_allowed!(classroom, connection_id) do
    changed? = connection_id != classroom.github_connection_id

    assignments_exist? =
      Repo.exists?(from(a in Assignment, where: a.classroom_id == ^classroom.id))

    if changed? and assignments_exist?, do: Repo.rollback(:organization_locked)
  end

  defp validate_connection_access!(actor, connection_id) do
    case validate_connection_access(actor, connection_id) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp delete_empty_classroom(classroom_id) do
    case Repo.transaction(fn -> delete_empty_classroom_locked!(classroom_id) end) do
      {:ok, deleted} -> {:ok, deleted}
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_empty_classroom_locked!(classroom_id) do
    Repo.query!("SELECT id FROM classrooms WHERE id = $1 FOR UPDATE", [classroom_id])

    if classroom_has_content?(classroom_id), do: Repo.rollback(:not_empty)

    Repo.get!(Classroom, classroom_id) |> Repo.delete!()
  end

  @doc "Archives a classroom without removing students or repositories."
  def archive_classroom(%User{} = actor, classroom_id),
    do: set_classroom_archive(actor, classroom_id, DateTime.utc_now())

  def archive_classroom(_, _), do: {:error, :unauthorized}

  @doc "Restores an archived classroom."
  def unarchive_classroom(%User{} = actor, classroom_id),
    do: set_classroom_archive(actor, classroom_id, nil)

  def unarchive_classroom(_, _), do: {:error, :unauthorized}

  @doc "Deletes an empty classroom. Classes with rosters or assignments must be archived instead."
  def delete_classroom(%User{} = actor, classroom_id) do
    with :ok <- require_classroom_teacher(actor, classroom_id),
         %Classroom{} <- Repo.get(Classroom, classroom_id),
         {:ok, deleted} <- delete_empty_classroom(classroom_id) do
      {:ok, deleted}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def delete_classroom(_, _), do: {:error, :unauthorized}

  @doc "Returns active classroom students with their institution profiles."
  def list_students(actor, classroom_id, opts \\ [])

  def list_students(%User{} = actor, classroom_id, opts) do
    with :ok <- require_classroom_teacher(actor, classroom_id) do
      include_removed? = Keyword.get(opts, :include_removed, false)

      rows =
        from(m in ClassroomStudent,
          where: m.classroom_id == ^classroom_id,
          where: ^include_removed? or is_nil(m.removed_at),
          order_by: [asc: m.joined_at],
          preload: [:user]
        )
        |> Repo.all()

      users = Accounts.with_student_profiles(Enum.map(rows, & &1.user))
      profiles = Map.new(users, &{&1.id, &1})
      {:ok, Enum.map(rows, &%{&1 | user: Map.fetch!(profiles, &1.user_id)})}
    end
  end

  def list_students(_, _, _), do: {:error, :unauthorized}

  @doc "Removes a student from a classroom without revoking access to accepted assignment repositories."
  def remove_student(%User{} = actor, classroom_id, student_user_id)
      when is_integer(classroom_id) and is_integer(student_user_id) do
    with :ok <- require_classroom_teacher(actor, classroom_id),
         %ClassroomStudent{} = member <- active_classroom_student(classroom_id, student_user_id) do
      member
      |> ClassroomStudent.changeset(%{removed_at: DateTime.utc_now()})
      |> Repo.update()
      |> case do
        {:ok, removed} ->
          broadcast({"classroom:#{classroom_id}", {:student_removed, student_user_id}})
          broadcast({"user:#{student_user_id}", {:classroom_removed, classroom_id}})
          {:ok, removed}

        error ->
          error
      end
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def remove_student(_, _, _), do: {:error, :unauthorized}

  @doc "Returns the active classroom join link, creating one when the classroom has none."
  def create_class_invitation(%User{} = actor, classroom_id) do
    with :ok <- GradePush.Demo.ensure_invitations_enabled(),
         :ok <- require_classroom_teacher(actor, classroom_id),
         %Classroom{} <- Repo.get(Classroom, classroom_id) do
      Repo.transaction(fn ->
        Repo.query!("SELECT id FROM classrooms WHERE id = $1 FOR UPDATE", [classroom_id])
        get_or_create_class_invitation!(actor, classroom_id)
      end)
      |> transaction_result()
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def revoke_class_invitation(%User{} = actor, classroom_id) do
    with :ok <- require_classroom_teacher(actor, classroom_id) do
      now = DateTime.utc_now()

      {count, _} =
        from(i in Invitation,
          where: i.classroom_id == ^classroom_id and is_nil(i.revoked_at)
        )
        |> Repo.update_all(set: [revoked_at: now, updated_at: now])

      if count > 0, do: broadcast({"classroom:#{classroom_id}", :invitation_revoked})
      {:ok, count}
    end
  end

  def revoke_class_invitation(_, _), do: {:error, :unauthorized}

  @doc "Looks up a classroom invitation without exposing its roster."
  def classroom_invitation(token) do
    with :ok <- GradePush.Demo.ensure_invitations_enabled(),
         %Invitation{} = invitation <- valid_invitation(Invitation, token),
         %Classroom{} = classroom <- Repo.get(Classroom, invitation.classroom_id) do
      {:ok,
       %{
         classroom:
           Map.take(classroom, [
             :id,
             :slug,
             :title,
             :code,
             :description,
             :semester,
             :academic_year
           ]),
         invitation: invitation_summary(invitation)
       }}
    else
      nil -> {:error, :invalid_invitation}
      error -> error
    end
  end

  @doc "Accepts a classroom link, records the student profile, and reactivates an existing enrollment if present."
  def accept_class_invitation(%User{id: user_id} = actor, token, profile_attrs)
      when is_integer(user_id) and is_map(profile_attrs) do
    with :ok <- GradePush.Demo.ensure_invitations_enabled(),
         true <- eligible_invitation_student?(actor),
         %Invitation{} = invitation <- valid_invitation(Invitation, token) do
      Repo.transaction(fn ->
        accept_class_invitation_locked!(actor, invitation, profile_attrs)
      end)
      |> publish_class_acceptance(actor)
    else
      false -> {:error, :unauthorized}
      nil -> {:error, :invalid_invitation}
      error -> error
    end
  end

  def accept_class_invitation(_, _, _), do: {:error, :unauthorized}

  defp accept_class_invitation_locked!(actor, invitation, profile_attrs) do
    classroom_id = invitation.classroom_id
    Repo.query!("SELECT id FROM classrooms WHERE id = $1 FOR UPDATE", [classroom_id])
    _invitation = valid_invitation_for_update!(invitation.id)
    classroom = Repo.get!(Classroom, classroom_id)

    if classroom.archived_at, do: Repo.rollback(:classroom_archived)

    ensure_student_profile_for_transaction!(actor, profile_attrs)
    enrollment = enroll_in_classroom!(classroom.id, actor.id)

    %{classroom: classroom, enrollment: enrollment}
  end

  defp valid_invitation_for_update!(invitation_id) do
    now = DateTime.utc_now()

    Repo.one(
      from(i in Invitation,
        where:
          i.id == ^invitation_id and is_nil(i.revoked_at) and
            (is_nil(i.expires_at) or i.expires_at > ^now),
        lock: "FOR SHARE"
      )
    ) || Repo.rollback(:invalid_invitation)
  end

  defp ensure_student_profile_for_transaction!(actor, profile_attrs) do
    case ensure_student_profile!(actor, profile_attrs) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp enroll_in_classroom!(classroom_id, user_id) do
    enrollment =
      Repo.get_by(ClassroomStudent, classroom_id: classroom_id, user_id: user_id) ||
        %ClassroomStudent{classroom_id: classroom_id, user_id: user_id}

    enrollment
    |> ClassroomStudent.changeset(%{
      joined_at: enrollment.joined_at || DateTime.utc_now(),
      removed_at: nil
    })
    |> Repo.insert_or_update!()
  end

  defp publish_class_acceptance({:ok, accepted}, actor) do
    broadcast(
      {"classroom:#{accepted.classroom.id}", {:student_joined, accepted.enrollment.user_id}}
    )

    broadcast({"user:#{actor.id}", {:classroom_joined, accepted.classroom.id}})
    {:ok, accepted}
  end

  defp publish_class_acceptance(error, _actor), do: error

  @doc "Adds an admitted institution teacher as an equal classroom collaborator."
  def add_teacher(%User{} = actor, classroom_id, teacher_user_id) do
    with :ok <- require_classroom_teacher(actor, classroom_id),
         true <- is_integer(teacher_user_id) and eligible_teacher?(teacher_user_id),
         %Classroom{} <- Repo.get(Classroom, classroom_id) do
      %ClassroomTeacher{classroom_id: classroom_id, user_id: teacher_user_id}
      |> Ecto.Changeset.change()
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:classroom_id, :user_id])
      |> case do
        {:ok, _} -> {:ok, teachers_for(classroom_id)}
        error -> error
      end
    else
      false -> {:error, :invalid_teacher}
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def add_teacher(_, _, _), do: {:error, :unauthorized}

  @doc "Removes a classroom collaborator while preserving the last-teacher invariant."
  def remove_teacher(%User{} = actor, classroom_id, teacher_user_id) do
    with :ok <- require_classroom_teacher(actor, classroom_id) do
      remove_classroom_teacher(classroom_id, teacher_user_id)
    end
  end

  def remove_teacher(_, _, _), do: {:error, :unauthorized}

  defp remove_classroom_teacher(classroom_id, teacher_user_id) do
    Repo.transaction(fn -> remove_classroom_teacher_locked!(classroom_id, teacher_user_id) end)
  end

  defp remove_classroom_teacher_locked!(classroom_id, teacher_user_id) do
    Repo.query!("SELECT id FROM classrooms WHERE id = $1 FOR UPDATE", [classroom_id])

    membership =
      Repo.get_by(ClassroomTeacher, classroom_id: classroom_id, user_id: teacher_user_id)

    cond do
      is_nil(membership) -> Repo.rollback(:not_found)
      classroom_teacher_count(classroom_id) <= 1 -> Repo.rollback(:last_teacher)
      true -> Repo.delete!(membership)
    end

    teachers_for(classroom_id)
  end

  defp classroom_teacher_count(classroom_id) do
    Repo.aggregate(from(t in ClassroomTeacher, where: t.classroom_id == ^classroom_id), :count)
  end

  @doc "Adds an admitted teacher and optionally replaces a classroom teacher through the institution-admin workflow."
  def reassign_teacher(%User{} = actor, classroom_id, add_user_id, replace_user_id \\ nil) do
    with true <- Accounts.admin?(actor),
         true <-
           is_integer(add_user_id) and add_user_id != actor.id and eligible_teacher?(add_user_id),
         %Classroom{} <- Repo.get(Classroom, classroom_id) do
      reassign_classroom_teacher(classroom_id, add_user_id, replace_user_id, actor)
    else
      false -> {:error, :unauthorized}
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp reassign_classroom_teacher(classroom_id, add_user_id, replace_user_id, actor) do
    Repo.transaction(fn ->
      Repo.query!("SELECT id FROM classrooms WHERE id = $1 FOR UPDATE", [classroom_id])
      classroom = Repo.get!(Classroom, classroom_id)
      add_classroom_teacher!(classroom_id, add_user_id)
      replace_classroom_teacher!(classroom_id, add_user_id, replace_user_id)
      record_teacher_reassignment!(actor, classroom, add_user_id, replace_user_id)
      teachers_for(classroom_id)
    end)
  end

  defp add_classroom_teacher!(classroom_id, user_id) do
    case Repo.insert(
           %ClassroomTeacher{classroom_id: classroom_id, user_id: user_id}
           |> Ecto.Changeset.change(),
           on_conflict: :nothing,
           conflict_target: [:classroom_id, :user_id]
         ) do
      {:ok, _membership} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp replace_classroom_teacher!(classroom_id, add_user_id, replace_user_id)
       when is_integer(replace_user_id) and replace_user_id != add_user_id do
    ensure_replaceable_teacher!(classroom_id, replace_user_id)

    from(t in ClassroomTeacher,
      where: t.classroom_id == ^classroom_id and t.user_id == ^replace_user_id
    )
    |> Repo.delete_all()
  end

  defp replace_classroom_teacher!(_classroom_id, _add_user_id, _replace_user_id), do: :ok

  defp ensure_replaceable_teacher!(classroom_id, replace_user_id) do
    assigned? =
      Repo.exists?(
        from(t in ClassroomTeacher,
          where: t.classroom_id == ^classroom_id and t.user_id == ^replace_user_id
        )
      )

    cond do
      not assigned? -> Repo.rollback(:teacher_not_assigned)
      classroom_teacher_count(classroom_id) <= 1 -> Repo.rollback(:last_teacher)
      true -> :ok
    end
  end

  defp record_teacher_reassignment!(actor, classroom, add_user_id, replace_user_id) do
    case Accounts.record_audit(
           actor,
           :institution,
           "classroom.teacher_reassigned",
           "classroom",
           classroom.id,
           classroom.title,
           %{added_user_id: add_user_id, replaced_user_id: replace_user_id}
         ) do
      {:ok, _event} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc "Resolves an admitted teacher by GitHub login for classroom collaboration."
  def find_teacher(%User{} = actor, login) when is_binary(login) do
    if instructional_member?(actor) do
      from(user in User,
        join: member in InstitutionMembership,
        on: member.user_id == user.id,
        where: fragment("lower(?) = lower(?)", user.login, ^String.trim(login)),
        where: member.role in [:teacher, :admin],
        select: user,
        limit: 1
      )
      |> Repo.one()
    end
  end

  def find_teacher(_, _), do: nil

  @doc "Lists class metadata and teacher names for a student already enrolled in the class."
  def list_student_classrooms(%User{id: user_id} = actor) when is_integer(user_id) do
    if Accounts.student?(actor) do
      classrooms =
        from(c in Classroom,
          join: m in ClassroomStudent,
          on: m.classroom_id == c.id and m.user_id == ^user_id and is_nil(m.removed_at),
          where: is_nil(c.archived_at),
          order_by: [asc: c.title]
        )
        |> Repo.all()

      {:ok, hydrate_classrooms(classrooms, :published)}
    else
      {:error, :unauthorized}
    end
  end

  def list_student_classrooms(_), do: {:error, :unauthorized}

  def list_student_classes(actor), do: list_student_classrooms(actor)

  @doc "Fetches one classroom for an active student enrollment without returning its roster."
  def get_student_classroom(%User{id: user_id} = actor, slug) when is_integer(user_id) do
    if Accounts.student?(actor) do
      result =
        from(c in Classroom,
          join: m in ClassroomStudent,
          on: m.classroom_id == c.id and m.user_id == ^user_id and is_nil(m.removed_at),
          where: c.slug == ^slug and is_nil(c.archived_at)
        )
        |> Repo.one()

      case result do
        nil -> {:error, :not_found}
        classroom -> {:ok, hydrate_classroom(classroom)}
      end
    else
      {:error, :unauthorized}
    end
  end

  def get_student_classroom(_, _), do: {:error, :unauthorized}

  @doc "Verifies an installation through the actor's GitHub account before connecting its organization."
  def connect_github_organization(actor, installation_id, sharing_scope \\ "private")

  def connect_github_organization(
        %User{id: user_id} = actor,
        installation_id,
        sharing_scope
      )
      when is_integer(user_id) and is_integer(installation_id) do
    with true <- Accounts.teacher?(actor),
         true <- sharing_scope in ~w(private institution),
         {:ok, verified} <-
           GradePush.Installation.verify_user_installation(actor, installation_id),
         account when is_map(account) <- verified.account,
         true <- account.type == "Organization" do
      persist_github_connection(actor, verified, account, sharing_scope)
    else
      false -> {:error, :unauthorized}
      nil -> {:error, :invalid_installation}
      error -> error
    end
  end

  def connect_github_organization(_, _, _), do: {:error, :unauthorized}

  defp persist_github_connection(actor, verified, account, sharing_scope) do
    attrs = %{
      github_organization_id: account.id,
      login: account.login,
      installation_id: verified.id,
      sharing_scope: sharing_scope,
      connected_by_id: actor.id,
      status: "active"
    }

    case Repo.insert(GitHubConnection.changeset(%GitHubConnection{}, attrs)) do
      {:ok, connection} ->
        broadcast({"github-connection:#{connection.id}", :connected})
        {:ok, connection}

      {:error, changeset} ->
        if Keyword.has_key?(changeset.errors, :github_organization_id),
          do: {:error, :organization_already_connected},
          else: {:error, changeset}
    end
  end

  @doc "Disables connections after GitHub revokes or suspends an installation."
  def handle_github_installation_event(
        installation_id,
        action,
        _added_repository_ids,
        _removed_repository_ids
      )
      when is_integer(installation_id) and action in ["deleted", "suspend", "unsuspend"] do
    status =
      if action == "deleted",
        do: "revoked",
        else: if(action == "suspend", do: "suspended", else: "active")

    {count, _} =
      Repo.update_all(
        from(connection in GitHubConnection,
          where: connection.installation_id == ^installation_id
        ),
        set: [status: status, updated_at: DateTime.utc_now()]
      )

    if count > 0 do
      broadcast({"github-installation:#{installation_id}", {:status_changed, status}})
    end

    {:ok, count}
  end

  def handle_github_installation_event(_installation_id, _action, _added, _removed),
    do: {:error, :unsupported_installation_event}

  @doc "Lists organization connections the actor may use."
  def list_github_connections(%User{id: user_id} = actor) when is_integer(user_id) do
    if instructional_member?(actor) do
      connections =
        from(c in GitHubConnection,
          left_join: s in GitHubConnectionTeacher,
          on: s.connection_id == c.id and s.user_id == ^user_id,
          where:
            c.connected_by_id == ^user_id or c.sharing_scope == "institution" or
              not is_nil(s.user_id),
          order_by: [asc: c.login],
          preload: [:authorized_teachers]
        )
        |> Repo.all()

      {:ok, connections}
    else
      {:error, :unauthorized}
    end
  end

  def list_github_connections(_), do: {:error, :unauthorized}

  @doc "Grants an admitted teacher permission to use a privately shared GitHub organization connection."
  def share_github_connection(%User{} = actor, connection_id, teacher_user_id) do
    with true <- instructional_member?(actor),
         %GitHubConnection{} = connection <- Repo.get(GitHubConnection, connection_id),
         true <- connection.connected_by_id == actor.id,
         true <- eligible_teacher?(teacher_user_id) do
      %GitHubConnectionTeacher{connection_id: connection_id, user_id: teacher_user_id}
      |> Ecto.Changeset.change()
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:connection_id, :user_id])
    else
      false -> {:error, :unauthorized}
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def share_github_connection(_, _, _), do: {:error, :unauthorized}

  @doc "Returns one organization connection only when the actor may use it."
  def get_github_connection(%User{id: user_id} = actor, connection_id)
      when is_integer(user_id) and is_integer(connection_id) do
    if instructional_member?(actor) do
      case authorized_connection_query(user_id, connection_id) |> Repo.one() do
        nil -> {:error, :not_found}
        connection -> {:ok, connection}
      end
    else
      {:error, :unauthorized}
    end
  end

  def get_github_connection(_, _), do: {:error, :unauthorized}

  @doc "Lists starter repositories available in the selected organization."
  def list_templates(%User{} = actor, classroom_id) do
    with :ok <- require_classroom_teacher(actor, classroom_id),
         %Classroom{github_connection_id: connection_id} when not is_nil(connection_id) <-
           Repo.get(Classroom, classroom_id),
         {:ok, %GitHubConnection{status: "active"} = connection} <-
           get_github_connection(actor, connection_id),
         {:ok, credentials} <- GradePush.Installation.github_app_credentials(),
         {:ok, token_response} <-
           GradePush.GitHub.installation_token(credentials, connection.installation_id),
         access_token when is_binary(access_token) <- field(token_response, :token),
         {:ok, repositories} <-
           GradePush.GitHub.list_template_repositories(access_token, connection.login) do
      {:ok,
       Enum.map(repositories, fn repository ->
         %{
           name: field(repository, :name),
           full_name: field(repository, :full_name),
           description: field(repository, :description)
         }
       end)}
    else
      nil -> {:error, :not_found}
      %Classroom{} -> {:error, :github_connection_unavailable}
      error -> error
    end
  end

  def list_templates(_, _), do: {:error, :unauthorized}

  def template_repository_available?(%User{} = actor, classroom_id, full_name)
      when is_integer(classroom_id) and is_binary(full_name) do
    candidate = String.downcase(String.trim(full_name))

    with [owner, repository] when owner != "" and repository != "" <-
           String.split(candidate, "/", parts: 2),
         {:ok, templates} <- list_templates(actor, classroom_id),
         true <- Enum.any?(templates, &(String.downcase(&1.full_name) == candidate)) do
      :ok
    else
      false -> {:error, :template_not_available}
      {:error, _reason} = error -> error
      _parts -> {:error, :invalid_template_repository}
    end
  end

  def template_repository_available?(_, _, _), do: {:error, :invalid_template_repository}

  def authorized_connection?(%User{id: user_id}, connection_id) when is_integer(user_id) do
    not is_nil(authorized_connection_query(user_id, connection_id) |> Repo.one())
  end

  def authorized_connection?(_, _), do: false

  defp set_classroom_archive(actor, classroom_id, archived_at) do
    with :ok <- require_classroom_teacher(actor, classroom_id),
         %Classroom{} = classroom <- Repo.get(Classroom, classroom_id) do
      classroom
      |> Ecto.Changeset.change(archived_at: archived_at)
      |> Repo.update()
      |> case do
        {:ok, updated} ->
          broadcast({"classroom:#{updated.id}", {:classroom_archived, not is_nil(archived_at)}})
          {:ok, updated}

        error ->
          error
      end
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp require_classroom_teacher(%User{id: user_id} = actor, classroom_id)
       when is_integer(user_id) and is_integer(classroom_id) do
    if instructional_member?(actor) and classroom_teacher?(user_id, classroom_id),
      do: :ok,
      else: {:error, :not_found}
  end

  defp require_classroom_teacher(_, _), do: {:error, :unauthorized}

  defp classroom_teacher?(user_id, classroom_id) do
    Repo.exists?(
      from(t in ClassroomTeacher,
        where: t.user_id == ^user_id and t.classroom_id == ^classroom_id
      )
    )
  end

  defp instructional_member?(actor),
    do: Accounts.teacher?(actor) or Accounts.admin?(actor)

  defp eligible_teacher?(user_id) when is_integer(user_id) do
    case Accounts.get_user(user_id) do
      %User{} = user -> instructional_member?(user)
      _ -> false
    end
  end

  defp eligible_teacher?(_), do: false

  defp active_classroom_student(classroom_id, student_user_id) do
    Repo.one(
      from(student in ClassroomStudent,
        where:
          student.classroom_id == ^classroom_id and student.user_id == ^student_user_id and
            is_nil(student.removed_at)
      )
    )
  end

  defp classroom_has_content?(classroom_id) do
    Repo.exists?(from(m in ClassroomStudent, where: m.classroom_id == ^classroom_id)) or
      Repo.exists?(from(a in Assignment, where: a.classroom_id == ^classroom_id))
  end

  defp admin_metadata(classroom) do
    teachers =
      Enum.map(classroom.teachers, &%{id: &1.user_id, name: &1.user.name, login: &1.user.login})

    %{
      classroom:
        Map.take(classroom, [
          :id,
          :slug,
          :title,
          :code,
          :semester,
          :academic_year,
          :archived_at,
          :inserted_at
        ]),
      students_count: classroom.students_count,
      assignments_count: classroom.assignments_count,
      teachers: teachers
    }
  end

  defp hydrate_classrooms(classrooms, assignment_filter \\ :active) do
    ids = Enum.map(classrooms, & &1.id)
    student_counts = counts_by_classroom(ClassroomStudent, ids, :active)
    assignment_counts = counts_by_classroom(Assignment, ids, assignment_filter)
    teacher_counts = counts_by_classroom(ClassroomTeacher, ids, :all)
    classrooms = Repo.preload(classrooms, [:github_connection, teachers: :user])

    Enum.map(classrooms, fn classroom ->
      %{
        classroom
        | students_count: Map.get(student_counts, classroom.id, 0),
          assignments_count: Map.get(assignment_counts, classroom.id, 0),
          teachers_count: Map.get(teacher_counts, classroom.id, 0)
      }
    end)
  end

  defp hydrate_classroom(classroom) do
    [classroom]
    |> hydrate_classrooms()
    |> List.first()
  end

  defp counts_by_classroom(_schema, [], _filter), do: %{}

  defp counts_by_classroom(schema, ids, filter) do
    query = from(record in schema, where: record.classroom_id in ^ids)

    query =
      case {schema, filter} do
        {ClassroomStudent, :active} ->
          from(record in query, where: is_nil(record.removed_at))

        {Assignment, :active} ->
          from(record in query, where: is_nil(record.archived_at))

        {Assignment, :published} ->
          from(record in query,
            where: is_nil(record.archived_at) and not is_nil(record.published_at)
          )

        _ ->
          query
      end

    query
    |> group_by([record], record.classroom_id)
    |> select([record], {record.classroom_id, count()})
    |> Repo.all()
    |> Map.new()
  end

  defp teachers_for(classroom_id) do
    from(t in ClassroomTeacher,
      where: t.classroom_id == ^classroom_id,
      order_by: [asc: t.inserted_at],
      preload: [:user]
    )
    |> Repo.all()
  end

  defp valid_invitation(schema, token) do
    now = DateTime.utc_now()
    hash = Token.digest(token)

    Repo.one(
      from(i in schema,
        where:
          i.token_hash == ^hash and is_nil(i.revoked_at) and
            (is_nil(i.expires_at) or i.expires_at > ^now)
      )
    )
  end

  defp active_class_invitation(classroom_id) do
    Repo.one(
      from(i in Invitation,
        where: i.classroom_id == ^classroom_id and is_nil(i.revoked_at),
        lock: "FOR UPDATE",
        limit: 1
      )
    )
  end

  defp get_or_create_class_invitation!(actor, classroom_id) do
    case active_class_invitation(classroom_id) do
      %Invitation{} = invitation ->
        reuse_or_rotate_class_invitation!(actor, classroom_id, invitation)

      nil ->
        create_class_invitation!(actor, classroom_id)
    end
  end

  defp reuse_or_rotate_class_invitation!(actor, classroom_id, invitation) do
    if invitation_active?(invitation) do
      decrypt_class_invitation!(invitation, classroom_id)
    else
      Repo.update!(Ecto.Changeset.change(invitation, revoked_at: DateTime.utc_now()))
      create_class_invitation!(actor, classroom_id)
    end
  end

  defp decrypt_class_invitation!(invitation, classroom_id) do
    case decrypt_invitation_token(invitation, classroom_id) do
      {:ok, token} -> %{invitation: invitation_summary(invitation), token: token}
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp create_class_invitation!(actor, classroom_id) do
    {token, token_hash} = Token.generate()

    case Crypto.encrypt(token, class_invitation_purpose(classroom_id)) do
      {:ok, token_encrypted} ->
        invitation =
          %Invitation{classroom_id: classroom_id, created_by_id: actor.id}
          |> Invitation.changeset(%{token_hash: token_hash, token_encrypted: token_encrypted})
          |> Repo.insert!()

        %{invitation: invitation_summary(invitation), token: token}

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp decrypt_invitation_token(invitation, classroom_id) do
    Crypto.decrypt(invitation.token_encrypted, class_invitation_purpose(classroom_id))
  end

  defp class_invitation_purpose(classroom_id), do: "classroom-invitation:#{classroom_id}"

  defp invitation_summary(invitation), do: Map.take(invitation, [:id, :expires_at, :revoked_at])

  defp invitation_active?(%Invitation{expires_at: nil}), do: true

  defp invitation_active?(%Invitation{expires_at: expires_at}),
    do: DateTime.compare(expires_at, DateTime.utc_now()) == :gt

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

  defp transaction_result({:ok, result}), do: {:ok, result}
  defp transaction_result({:error, reason}), do: {:error, reason}

  defp eligible_invitation_student?(%User{} = actor),
    do: not Accounts.teacher?(actor) and not Accounts.admin?(actor)

  defp validate_connection_access(_actor, nil), do: :ok

  defp validate_connection_access(actor, connection_id) when is_integer(connection_id) do
    if authorized_connection?(actor, connection_id), do: :ok, else: {:error, :invalid_connection}
  end

  defp validate_connection_access(_actor, _), do: {:error, :invalid_connection}

  defp authorized_connection_query(user_id, connection_id) do
    from(c in GitHubConnection,
      left_join: s in GitHubConnectionTeacher,
      on: s.connection_id == c.id and s.user_id == ^user_id,
      where:
        c.id == ^connection_id and
          c.status == "active" and
          (c.connected_by_id == ^user_id or c.sharing_scope == "institution" or
             not is_nil(s.user_id))
    )
  end

  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp field(_, _), do: nil

  defp available_classroom_slug(attrs) do
    base = slugify(attrs[:code] || attrs[:title] || "classroom")
    candidate = if base == "", do: "classroom", else: base
    suffix = Base.url_encode64(:crypto.strong_rand_bytes(3), padding: false) |> String.downcase()
    slug = "#{String.slice(candidate, 0, 68)}-#{suffix}"

    if Repo.exists?(from(c in Classroom, where: c.slug == ^slug)),
      do: {:error, :slug_conflict},
      else: {:ok, slug}
  end

  defp normalize_classroom_attrs(attrs, actor) do
    attrs = Map.new(attrs, fn {key, value} -> {normalize_key(key), value} end)

    attrs
    |> Map.update(:title, nil, &localized_value(&1, actor.locale))
    |> Map.update(:description, "", &localized_value(&1, actor.locale))
  end

  defp localized_value(value, _locale) when is_binary(value), do: String.trim(value)

  defp localized_value(value, locale) when is_map(value) do
    Map.get(value, String.to_existing_atom(locale)) || Map.get(value, locale) ||
      value |> Map.values() |> Enum.find(&is_binary/1) || ""
  end

  defp localized_value(_, _), do: ""

  defp broadcast({topic, message}),
    do: Phoenix.PubSub.broadcast(GradePush.PubSub, topic, message)

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    case key do
      "github_connection_id" -> :github_connection_id
      "title" -> :title
      "code" -> :code
      "description" -> :description
      "semester" -> :semester
      "academic_year" -> :academic_year
      _ -> key
    end
  end

  defp slugify(value) do
    value
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/[\x{0300}-\x{036f}]/u, "")
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
