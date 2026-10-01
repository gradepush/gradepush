defmodule GradePush.MembershipTransactionTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias GradePush.{Accounts, Assignments, Classrooms, Repo}
  alias GradePush.Accounts.{Institution, User}
  alias GradePush.Assignments.{Assignment, Repository, Subject, TeamMember}
  alias GradePush.Classrooms.{Classroom, ClassroomStudent, ClassroomTeacher, GitHubConnection}
  alias GradePush.Installation.GitHubApp

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    %{user: owner, institution: institution} = bootstrap_fixture()
    colleague = user_fixture()
    teacher_membership_fixture(colleague)
    candidate = user_fixture()
    teacher_membership_fixture(candidate)
    classroom = classroom_fixture(owner)
    authorize_github_fixture(colleague)
    {:ok, _} = Classrooms.connect_github_organization(colleague, 123)
    {:ok, _} = Classrooms.add_teacher(owner, classroom.id, colleague.id)
    assignment = assignment_fixture(owner, classroom)
    app = Repo.one!(GitHubApp)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        subject_ids = Repo.all(from(s in Subject, select: s.id))

        Repo.delete_all(
          from(j in Oban.Job,
            where: fragment("(?->>'subject_id')::bigint", j.args) in ^subject_ids
          )
        )

        Repo.delete_all(from(c in Classroom, where: c.created_by_id == ^owner.id))
        Repo.delete_all(from(c in GitHubConnection, where: c.connected_by_id == ^owner.id))

        Repo.delete_all(
          from(a in GradePush.Accounts.AuditEvent,
            where: a.actor_id in ^[owner.id, colleague.id, candidate.id]
          )
        )

        Repo.delete_all(from(i in Institution, where: i.id == ^institution.id))

        Repo.delete_all(
          from(u in User,
            where:
              u.id in ^[owner.id, colleague.id, candidate.id] or
                like(u.login, "transaction-student-%")
          )
        )

        Repo.delete_all(from(a in GitHubApp, where: a.id == ^app.id))
      end)
    end)

    %{
      owner: owner,
      colleague: colleague,
      candidate: candidate,
      classroom: classroom,
      assignment: assignment
    }
  end

  test "a queued collaborator removal cannot use the removed actor's grant", c do
    assert {:error, :not_found} =
             after_change(
               fn ->
                 assert {:ok, _} =
                          Classrooms.remove_teacher(c.owner, c.classroom.id, c.colleague.id)
               end,
               fn -> Classrooms.remove_teacher(c.colleague, c.classroom.id, c.owner.id) end
             )

    assert Repo.exists?(
             from(t in ClassroomTeacher,
               where: t.classroom_id == ^c.classroom.id and t.user_id == ^c.owner.id
             )
           )
  end

  test "a queued assignment edit is denied after classroom access is removed", c do
    Phoenix.PubSub.subscribe(GradePush.PubSub, "classroom:#{c.classroom.id}")

    assert {:error, :not_found} =
             after_change(
               fn ->
                 assert {:ok, _} =
                          Classrooms.remove_teacher(c.owner, c.classroom.id, c.colleague.id)
               end,
               fn ->
                 Assignments.update_assignment(c.colleague, c.assignment.id, %{
                   title: "Queued edit"
                 })
               end
             )

    assert Repo.get!(Assignment, c.assignment.id).title == c.assignment.title
    refute_receive {:assignment_updated, _}
  end

  test "admin reassignment observes a role change committed during its wait", c do
    assert {:ok, _} = Accounts.change_role(c.owner, c.colleague.id, :admin)

    assert {:error, :unauthorized} =
             after_change(
               fn ->
                 assert {:ok, _} = Accounts.change_role(c.owner, c.colleague.id, :teacher)
               end,
               fn -> Classrooms.reassign_teacher(c.colleague, c.classroom.id, c.candidate.id) end
             )

    refute Repo.exists?(
             from(t in ClassroomTeacher,
               where: t.classroom_id == ^c.classroom.id and t.user_id == ^c.candidate.id
             )
           )
  end

  test "a queued student team join observes classroom removal", c do
    student = transaction_student()

    Repo.insert!(%ClassroomStudent{
      classroom_id: c.classroom.id,
      user_id: student.id,
      joined_at: DateTime.utc_now()
    })

    team_assignment =
      assignment_fixture(c.owner, c.classroom, %{kind: "team", team_mode: "students"})

    assert {:ok, team} =
             Assignments.create_team(c.owner, team_assignment.id, %{name: "Transaction team"})

    assert {:error, :unauthorized} =
             after_change(
               fn ->
                 assert {:ok, _} = Classrooms.remove_student(c.owner, c.classroom.id, student.id)
               end,
               fn -> Assignments.join_team(student, team_assignment.id, team.id) end
             )

    refute Repo.exists?(
             from(m in TeamMember, where: m.team_id == ^team.id and m.user_id == ^student.id)
           )
  end

  test "assignment acceptance rechecks a revoked invitation after the assignment wait", c do
    student = transaction_student()
    assert {:ok, invitation} = Assignments.create_assignment_invitation(c.owner, c.assignment.id)
    Phoenix.PubSub.subscribe(GradePush.PubSub, "assignment:#{c.assignment.id}")

    assert {:error, :invalid_invitation} =
             after_change(
               fn ->
                 assert {:ok, 1} =
                          Assignments.revoke_assignment_invitation(c.owner, c.assignment.id)
               end,
               fn -> Assignments.accept_assignment_invitation(student, invitation.token, %{}) end
             )

    assert_no_acceptance(c.assignment.id)
    refute_receive {:submission_changed, _}
  end

  test "assignment acceptance rechecks expiry after the assignment wait", c do
    student = transaction_student()
    assert {:ok, invitation} = Assignments.create_assignment_invitation(c.owner, c.assignment.id)
    expires = DateTime.add(DateTime.utc_now(), 1, :second)

    Repo.get!(GradePush.Assignments.Invitation, invitation.invitation.id)
    |> Ecto.Changeset.change(expires_at: expires)
    |> Repo.update!()

    assert {:error, :invalid_invitation} =
             after_change(
               fn ->
                 Repo.query!("SELECT id FROM assignments WHERE id = $1 FOR UPDATE", [
                   c.assignment.id
                 ])
               end,
               fn -> Assignments.accept_assignment_invitation(student, invitation.token, %{}) end,
               fn ->
                 wait_until(fn -> DateTime.compare(DateTime.utc_now(), expires) == :gt end)
               end
             )

    assert_no_acceptance(c.assignment.id)
  end

  defp transaction_student do
    student_fixture(%{login: "transaction-student-#{System.unique_integer([:positive])}"})
  end

  test "invitation creation and teacher addition do not block on the creator foreign key", c do
    {:ok, {waiter, invitation}} =
      Repo.transaction(fn ->
        Repo.query!("SET LOCAL statement_timeout = '3s'")
        Repo.query!("SELECT id FROM classrooms WHERE id = $1 FOR UPDATE", [c.classroom.id])
        Repo.query!("SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock'")

        {waiter, marker} =
          marked_operation(fn ->
            Classrooms.add_teacher(c.owner, c.classroom.id, c.colleague.id)
          end)

        wait_for_lock(marker)
        assert {:ok, invitation} = Classrooms.create_class_invitation(c.colleague, c.classroom.id)
        {waiter, invitation}
      end)

    assert invitation.token
    assert {:ok, _} = Task.await(waiter, 5000)
  end

  test "teacher team assignment and student acceptance do not block on the student foreign key",
       c do
    student = transaction_student()

    Repo.insert!(%ClassroomStudent{
      classroom_id: c.classroom.id,
      user_id: student.id,
      joined_at: DateTime.utc_now()
    })

    assignment = assignment_fixture(c.owner, c.classroom, %{kind: "team", team_mode: "teacher"})

    assert {:ok, team} =
             Assignments.create_team(c.owner, assignment.id, %{name: "Concurrent team"})

    assert {:ok, invitation} = Assignments.create_assignment_invitation(c.owner, assignment.id)

    {:ok, waiter} =
      Repo.transaction(fn ->
        Repo.query!("SET LOCAL statement_timeout = '3s'")
        Repo.query!("SELECT id FROM assignments WHERE id = $1 FOR UPDATE", [assignment.id])

        {waiter, marker} =
          marked_operation(fn ->
            Assignments.accept_assignment_invitation(student, invitation.token, %{
              team_id: team.id
            })
          end)

        wait_for_lock(marker)
        assert {:ok, _} = Assignments.add_team_member(c.owner, assignment.id, team.id, student.id)
        waiter
      end)

    assert {:ok, %{subject: %{team_id: team_id}}} = Task.await(waiter, 5000)
    assert team_id == team.id
  end

  test "classroom edits do not use a different organization than their GitHub preflight", c do
    classroom = classroom_fixture(c.owner)
    assert {:ok, _} = Classrooms.add_teacher(c.owner, classroom.id, c.colleague.id)

    other_connection =
      %GitHubConnection{
        github_organization_id: System.unique_integer([:positive]),
        login: "changed-organization",
        installation_id: 987,
        connected_by_id: c.owner.id,
        status: "active"
      }
      |> Repo.insert!()

    # This independent writer represents a second classroom edit committed
    # while the title-only edit waits for its classroom lock.
    assert {:error, :organization_changed} =
             after_change(
               fn ->
                 Repo.query!("SELECT id FROM classrooms WHERE id = $1 FOR UPDATE", [
                   classroom.id
                 ])

                 Repo.get!(Classroom, classroom.id)
                 |> Ecto.Changeset.change(github_connection_id: other_connection.id)
                 |> Repo.update!()
               end,
               fn ->
                 Classrooms.update_classroom(c.colleague, classroom.id, %{title: "Queued title"})
               end
             )

    assert Repo.get!(Classroom, classroom.id).title == classroom.title
  end

  defp assert_no_acceptance(assignment_id) do
    refute Repo.exists?(from(s in Subject, where: s.assignment_id == ^assignment_id))
    refute Repo.exists?(Repository)

    refute Repo.exists?(
             from(j in Oban.Job,
               where: j.worker == "GradePush.Workers.ProvisionAssignmentRepository"
             )
           )
  end

  # Each task checks out its own unsandboxed connection so PostgreSQL, rather
  # than a shared Sandbox connection, enforces the row-lock ordering.
  defp after_change(change, operation, while_waiting \\ fn -> :ok end) do
    parent = self()

    blocker =
      Task.async(fn ->
        connection(fn -> hold_change(change, parent) end)
      end)

    assert_receive {:change_pending, blocker_pid}, 5000

    {waiter, marker} = marked_operation(operation)

    try do
      wait_for_lock(marker)

      while_waiting.()
      send(blocker_pid, :commit_change)
      assert {:ok, :ok} = Task.await(blocker, 5000)
      Task.await(waiter, 5000)
    after
      Task.shutdown(blocker, :brutal_kill)
      Task.shutdown(waiter, :brutal_kill)
    end
  end

  defp hold_change(change, parent) do
    Repo.transaction(fn ->
      change.()
      send(parent, {:change_pending, self()})
      receive do: (:commit_change -> :ok)
    end)
  end

  defp marked_operation(operation) do
    marker = "gradepush-transaction-#{System.unique_integer([:positive])}"

    task =
      Task.async(fn ->
        connection(fn ->
          Repo.query!("SELECT set_config('application_name', $1, false)", [marker])
          operation.()
        end)
      end)

    {task, marker}
  end

  defp wait_for_lock(marker) do
    wait_until(fn ->
      # PostgreSQL caches activity snapshots inside transactions. Refresh before
      # polling so a task that starts after the first read can be observed.
      Repo.query!("SELECT pg_stat_clear_snapshot()")

      [[waiting]] =
        Repo.query!(
          "SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE application_name = $1 AND wait_event_type = 'Lock')",
          [marker]
        ).rows

      waiting
    end)
  end

  defp connection(fun) do
    :ok = Sandbox.checkout(Repo, sandbox: false)

    try do
      fun.()
    after
      Repo.query!("RESET application_name")
      Sandbox.checkin(Repo)
    end
  end

  defp wait_until(fun), do: wait_until(fun, System.monotonic_time(:millisecond) + 5000)

  defp wait_until(fun, deadline) do
    unless fun.() do
      assert System.monotonic_time(:millisecond) < deadline,
             "timed out waiting for the database boundary"

      Process.sleep(10)
      wait_until(fun, deadline)
    end
  end
end
