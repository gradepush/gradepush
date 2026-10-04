defmodule GradePush.TeamManagementTest do
  use GradePush.DataCase, async: false
  use Oban.Testing, repo: GradePush.Repo

  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures

  alias GradePush.{Assignments, Classrooms, Repo, Submissions}
  alias GradePush.Assignments.{Repository, Subject, Team, TeamMember}
  alias GradePush.GitHub.Fake
  alias GradePush.GitHub.Fake.Store
  alias GradePush.Workers.{ProvisionAssignmentRepository, SyncAssignmentRepositoryAccess}

  setup context do
    Fake.reset!()
    on_exit(&Fake.reset!/0)
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    mode = Map.get(context, :team_mode, "teacher")
    assignment = assignment_fixture(teacher, classroom, %{kind: "team", team_mode: mode})
    students = for _ <- 1..2, do: student_fixture()
    {:ok, invitation} = Classrooms.create_class_invitation(teacher, classroom.id)

    for student <- students,
        do: Classrooms.accept_class_invitation(student, invitation.token, %{})

    creator = if mode == "students", do: hd(students), else: teacher
    {:ok, team} = Assignments.create_team(creator, assignment.id, %{name: "Orion"})

    for student <- students do
      if mode == "students",
        do: Assignments.join_team(student, assignment.id, team.id),
        else: Assignments.add_team_member(teacher, assignment.id, team.id, student.id)
    end

    {:ok, invitation} = Assignments.create_assignment_invitation(teacher, assignment.id)

    {:ok, %{subject: subject}} =
      Assignments.accept_assignment_invitation(hd(students), invitation.token, %{})

    %{
      teacher: teacher,
      classroom: classroom,
      assignment: assignment,
      team: team,
      students: students,
      subject: subject,
      invitation: invitation
    }
  end

  for mode <- ["students", "teacher"] do
    @tag team_mode: mode
    test "teachers rebalance #{mode} teams and reconcile both repositories", c do
      [moved, remaining] = c.students
      assert :ok = provision(c.subject.id)
      old_repository = Repo.get_by!(Repository, subject_id: c.subject.id)
      newcomer = student_fixture()
      {:ok, class_invite} = Classrooms.create_class_invitation(c.teacher, c.classroom.id)
      {:ok, _} = Classrooms.accept_class_invitation(newcomer, class_invite.token, %{})
      {:ok, destination} = Assignments.create_team(c.teacher, c.assignment.id, %{name: "Lyra"})

      assert {:ok, _} =
               Assignments.add_team_member(
                 c.teacher,
                 c.assignment.id,
                 destination.id,
                 newcomer.id
               )

      {:ok, %{subject: target}} =
        Assignments.accept_assignment_invitation(newcomer, c.invitation.token, %{})

      assert :ok = provision(target.id)
      target_repository = Repo.get_by!(Repository, subject_id: target.id)

      assert {:error, :already_in_team} =
               Assignments.add_team_member(c.teacher, c.assignment.id, destination.id, moved.id)

      assert {:ok, _} =
               Assignments.remove_team_member(c.teacher, c.assignment.id, c.team.id, moved.id)

      assert {:ok, _} =
               Assignments.add_team_member(c.teacher, c.assignment.id, destination.id, moved.id)

      for subject <- [c.subject, target] do
        assert Repo.get_by!(Repository, subject_id: subject.id).access_sync_state == "pending"

        assert_enqueued(
          worker: SyncAssignmentRepositoryAccess,
          args: %{subject_id: subject.id}
        )
      end

      assert {:ok, view} =
               Assignments.get_student_assignment(moved, c.classroom.id, c.assignment.slug)

      assert view.subject.id == target.id
      assert {:ok, _} = Classrooms.get_student_classroom(moved, c.classroom.slug)
      assert :ok = sync(c.subject.id)
      assert :ok = sync(target.id)

      assert Fake.collaborators(old_repository.owner_login, old_repository.name) == [
               remaining.login
             ]

      assert Enum.sort(Fake.collaborators(target_repository.owner_login, target_repository.name)) ==
               Enum.sort([moved.login, newcomer.login])

      assert Repo.get!(Subject, c.subject.id)

      assert {:ok, %{subject: accepted}} =
               Assignments.accept_assignment_invitation(moved, c.invitation.token, %{})

      assert accepted.id == target.id
      assert :ok = sync(c.subject.id)
      refute moved.login in Fake.collaborators(old_repository.owner_login, old_repository.name)
    end
  end

  @tag team_mode: "students"
  test "student-formed teams keep teacher scope, capacity and enrollment checks", c do
    outsider = user_fixture()
    teacher_membership_fixture(outsider)
    unrostered = student_fixture()
    {:ok, destination} = Assignments.create_team(c.teacher, c.assignment.id, %{name: "Lyra"})

    for actor <- [hd(c.students), outsider] do
      assert {:error, _} =
               Assignments.add_team_member(actor, c.assignment.id, destination.id, unrostered.id)

      assert {:error, _} =
               Assignments.remove_team_member(
                 actor,
                 c.assignment.id,
                 c.team.id,
                 hd(c.students).id
               )
    end

    assert {:error, :student_not_enrolled} =
             Assignments.add_team_member(
               c.teacher,
               c.assignment.id,
               destination.id,
               unrostered.id
             )

    {:ok, class_invite} = Classrooms.create_class_invitation(c.teacher, c.classroom.id)
    {:ok, _} = Classrooms.accept_class_invitation(unrostered, class_invite.token, %{})

    assert {:error, :team_full} =
             Assignments.add_team_member(c.teacher, c.assignment.id, c.team.id, unrostered.id)

    other_assignment = assignment_fixture(c.teacher, c.classroom, %{kind: "team"})

    assert {:error, :not_found} =
             Assignments.add_team_member(
               c.teacher,
               other_assignment.id,
               destination.id,
               unrostered.id
             )
  end

  test "renaming validates names, keeps repository identity and cannot cross classroom scopes",
       c do
    assert :ok = provision(c.subject.id)
    repository = Repo.get_by!(Repository, subject_id: c.subject.id)

    assert {:ok, %{name: "Atlas"}} =
             Assignments.rename_team(c.teacher, c.assignment.id, c.team.id, %{name: " Atlas "})

    assert {:error, :team_name_required} =
             Assignments.rename_team(c.teacher, c.assignment.id, c.team.id, %{name: " "})

    assert {:error, %Ecto.Changeset{}} =
             Assignments.rename_team(c.teacher, c.assignment.id, c.team.id, %{
               name: String.duplicate("a", 121)
             })

    {:ok, other} = Assignments.create_team(c.teacher, c.assignment.id, %{name: "Other"})

    assert {:error, :already_in_team} =
             Assignments.add_team_member(c.teacher, c.assignment.id, other.id, hd(c.students).id)

    assert {:error, %Ecto.Changeset{}} =
             Assignments.rename_team(c.teacher, c.assignment.id, other.id, %{name: "Atlas"})

    other_assignment = assignment_fixture(c.teacher, c.classroom, %{kind: "team"})

    assert {:error, :not_found} =
             Assignments.delete_team(c.teacher, other_assignment.id, c.team.id)

    outsider = user_fixture()
    teacher_membership_fixture(outsider)

    for actor <- [hd(c.students), outsider] do
      assert {:error, _} =
               Assignments.rename_team(actor, c.assignment.id, c.team.id, %{name: "Denied"})

      assert {:error, _} =
               Assignments.remove_team_member(
                 actor,
                 c.assignment.id,
                 c.team.id,
                 hd(c.students).id
               )

      assert {:error, _} = Assignments.delete_team(actor, c.assignment.id, c.team.id)
      assert {:error, _} = Assignments.retry_repository_access(actor, c.subject.id)
    end

    assert :ok = provision(c.subject.id)
    assert Repo.get_by!(Repository, subject_id: c.subject.id).full_name == repository.full_name
  end

  test "removal revokes one member and their pending invitation while preserving other access",
       c do
    assert :ok = provision(c.subject.id)
    repository = Repo.get_by!(Repository, subject_id: c.subject.id)
    [removed, remaining] = c.students
    removed |> Ecto.Changeset.change(login: "reassigned-old-login") |> Repo.update!()

    Store.put({:repository_invitations, repository.owner_login, repository.name}, [
      %{"id" => 41, "invitee" => %{"id" => removed.github_id}},
      %{"id" => 42, "invitee" => %{"id" => 999}}
    ])

    {:ok, _} =
      Fake.add_collaborator(
        "token",
        repository.owner_login,
        repository.name,
        "unrelated-teacher",
        "push"
      )

    assert {:ok, _} =
             Assignments.remove_team_member(c.teacher, c.assignment.id, c.team.id, removed.id)

    assert Repo.get_by!(Repository, subject_id: c.subject.id).access_sync_state == "pending"
    assert Repo.get_by!(TeamMember, team_id: c.team.id, user_id: removed.id).left_at
    assert {:ok, [subject]} = Assignments.list_submissions(c.teacher, c.assignment.id)
    assert Enum.map(subject.team.members, & &1.user_id) == [remaining.id]

    assert {:ok, view} =
             Assignments.get_student_assignment(removed, c.classroom.id, c.assignment.slug)

    assert is_nil(view.subject)
    assert {:ok, _} = Classrooms.get_student_classroom(removed, c.classroom.slug)
    assert :ok = sync(c.subject.id)

    assert Enum.sort(Fake.collaborators(repository.owner_login, repository.name)) ==
             Enum.sort([remaining.login, "unrelated-teacher"])

    assert {:ok, [%{"id" => 42}]} =
             Fake.list_repository_invitations("token", repository.owner_login, repository.name)

    assert :ok = sync(c.subject.id)
    assert Repo.get_by!(Repository, subject_id: c.subject.id).access_sync_state == "synced"
  end

  test "deleting an accepted team retains submission evidence and releases its name and students",
       c do
    assert :ok = provision(c.subject.id)
    repository = Repo.get_by!(Repository, subject_id: c.subject.id)

    {:ok, push} =
      Submissions.record_push(
        c.assignment.id,
        repository.id,
        String.duplicate("a", 40),
        DateTime.utc_now(),
        "team-deletion-push"
      )

    assert {:ok, _} = Assignments.delete_team(c.teacher, c.assignment.id, c.team.id)
    assert {:ok, []} = Assignments.list_teams(c.teacher, c.assignment.id)
    assert Repo.get!(Team, c.team.id).archived_at
    assert Repo.get!(Subject, c.subject.id)
    assert Repo.get!(Submissions.Push, push.id)
    assert {:ok, [subject]} = Assignments.list_submissions(c.teacher, c.assignment.id)
    assert subject.team.members == []
    assert subject.latest_push.id == push.id
    assert :ok = sync(c.subject.id)
    assert Fake.collaborators(repository.owner_login, repository.name) == []
    assert :ok = provision(c.subject.id)
    assert Fake.collaborators(repository.owner_login, repository.name) == []

    assert {:ok, replacement} =
             Assignments.create_team(c.teacher, c.assignment.id, %{name: "Orion"})

    assert {:ok, _} =
             Assignments.add_team_member(
               c.teacher,
               c.assignment.id,
               replacement.id,
               hd(c.students).id
             )

    assert {:ok, %{subject: new_subject}} =
             Assignments.accept_assignment_invitation(hd(c.students), c.invitation.token, %{})

    refute new_subject.id == c.subject.id
    assert :ok = provision(new_subject.id)
    replacement_repository = Repo.get_by!(Repository, subject_id: new_subject.id)
    refute replacement_repository.name == repository.name
    refute replacement_repository.github_repository_id == repository.github_repository_id
  end

  test "a queued provision reads current membership and rejoining supersedes a pending removal",
       c do
    [removed, remaining] = c.students
    assert {:ok, _old_intent} = Assignments.provisioning_intent(c.subject.id)

    assert {:ok, _} =
             Assignments.remove_team_member(c.teacher, c.assignment.id, c.team.id, removed.id)

    assert :ok = provision(c.subject.id)
    repository = Repo.get_by!(Repository, subject_id: c.subject.id)
    assert Fake.collaborators(repository.owner_login, repository.name) == [remaining.login]
    old_version = repository.access_version

    assert {:ok, _} =
             Assignments.add_team_member(c.teacher, c.assignment.id, c.team.id, removed.id)

    Assignments.repository_access_synced(c.subject.id, old_version, :ok)
    assert Repo.get_by!(Repository, subject_id: c.subject.id).access_sync_state == "pending"
    assert :ok = sync(c.subject.id)

    assert Enum.sort(Fake.collaborators(repository.owner_login, repository.name)) ==
             Enum.sort(Enum.map(c.students, & &1.login))
  end

  test "a failed revocation stays visible and retries without affecting repository readiness",
       c do
    assert :ok = provision(c.subject.id)
    assert {:ok, _} = Assignments.delete_team(c.teacher, c.assignment.id, c.team.id)
    Fake.fail_next(:remove_collaborator, :forbidden)
    assert {:discard, "collaborator_setup_failed"} = sync(c.subject.id)

    assert %Repository{state: "ready", access_sync_state: "failed"} =
             Repo.get_by!(Repository, subject_id: c.subject.id)

    assert {:ok, %{access_sync_state: "pending"}} =
             Assignments.retry_repository_access(c.teacher, c.subject.id)

    assert :ok = sync(c.subject.id)
    assert Repo.get_by!(Repository, subject_id: c.subject.id).access_sync_state == "synced"
  end

  defp provision(subject_id), do: ProvisionAssignmentRepository.perform(job(subject_id))
  defp sync(subject_id), do: SyncAssignmentRepositoryAccess.perform(job(subject_id))
  defp job(id), do: %Oban.Job{args: %{"subject_id" => id}, attempt: 1, max_attempts: 10}
end
