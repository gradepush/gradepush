defmodule GradePush.StudentScheduleTest do
  use GradePush.DataCase, async: true

  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures

  alias GradePush.{Assignments, Classrooms, Repo, Submissions}

  test "schedule is scoped to active enrollments and published, unarchived assignments" do
    %{user: teacher} = bootstrap_fixture()
    student = student_fixture()
    classes = for _ <- 1..4, do: classroom_fixture(teacher)
    [active, removed, archived, other] = classes

    for classroom <- [active, removed, archived] do
      {:ok, invitation} = Classrooms.create_class_invitation(teacher, classroom.id)
      assert {:ok, _} = Classrooms.accept_class_invitation(student, invitation.token, %{})
    end

    visible = assignment_fixture(teacher, active)
    draft = assignment_fixture(teacher, active)
    draft |> Ecto.Changeset.change(published_at: nil) |> Repo.update!()
    hidden = assignment_fixture(teacher, active)
    assert {:ok, _} = Assignments.archive_assignment(teacher, hidden.id)
    for classroom <- [removed, archived, other], do: assignment_fixture(teacher, classroom)
    assert {:ok, _} = Classrooms.remove_student(teacher, removed.id, student.id)
    assert {:ok, _} = Classrooms.archive_classroom(teacher, archived.id)

    assert {:ok, [entry]} = Assignments.list_student_schedule(student)
    assert entry.assignment.id == visible.id
    assert entry.classroom.id == active.id
    assert {:ok, []} = Assignments.list_student_schedule(student_fixture())
    assert {:error, :unauthorized} = Assignments.list_student_schedule(teacher)
    assert {:error, :unauthorized} = Assignments.list_student_schedule(nil)
  end

  test "sorting uses only the student's extensions, includes unaccepted work, and puts undated work last" do
    %{user: teacher} = bootstrap_fixture()
    student = student_fixture()
    other = student_fixture()
    classroom = classroom_fixture(teacher)
    early = assignment_fixture(teacher, classroom)
    later = assignment_fixture(teacher, classroom)
    undated = assignment_fixture(teacher, classroom)
    first_due = ~U[2026-10-01 18:00:00.000000Z]
    later_due = ~U[2026-10-03 18:00:00.000000Z]
    extension = ~U[2026-10-05 18:00:00.000000Z]
    {:ok, _} = Assignments.update_assignment(teacher, early.id, %{deadline_at: first_due})
    {:ok, _} = Assignments.update_assignment(teacher, later.id, %{deadline_at: later_due})
    {:ok, invitation} = Assignments.create_assignment_invitation(teacher, early.id)

    {:ok, %{subject: subject}} =
      Assignments.accept_assignment_invitation(student, invitation.token, %{})

    {:ok, %{subject: other_subject}} =
      Assignments.accept_assignment_invitation(other, invitation.token, %{})

    {:ok, _} = Submissions.set_extension(teacher, early.id, other_subject.id, extension)
    {:ok, entries} = Assignments.list_student_schedule(student)
    assert Enum.map(entries, & &1.assignment.id) == [early.id, later.id, undated.id]
    assert hd(entries).deadline_at == first_due
    {:ok, _} = Submissions.set_extension(teacher, early.id, subject.id, extension)
    {:ok, entries} = Assignments.list_student_schedule(student)
    assert Enum.map(entries, & &1.assignment.id) == [later.id, early.id, undated.id]
    assert Enum.at(entries, 1).deadline_at == extension
  end

  test "a team deadline is visible only to its active members" do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    assignment = assignment_fixture(teacher, classroom, %{kind: "team"})
    deadline = ~U[2026-10-01 18:00:00.000000Z]
    extension = ~U[2026-10-05 18:00:00.000000Z]
    {:ok, _} = Assignments.update_assignment(teacher, assignment.id, %{deadline_at: deadline})
    {:ok, invitation} = Assignments.create_assignment_invitation(teacher, assignment.id)
    student = student_fixture()
    other = student_fixture()

    {:ok, %{subject: subject}} =
      Assignments.accept_assignment_invitation(student, invitation.token, %{team_name: "Team A"})

    {:ok, _} =
      Assignments.accept_assignment_invitation(other, invitation.token, %{team_name: "Team B"})

    {:ok, _} = Submissions.set_extension(teacher, assignment.id, subject.id, extension)
    assert {:ok, [%{deadline_at: ^extension}]} = Assignments.list_student_schedule(student)
    assert {:ok, [%{deadline_at: ^deadline}]} = Assignments.list_student_schedule(other)

    membership =
      Repo.get_by!(Assignments.TeamMember, user_id: student.id, team_id: subject.team_id)

    membership |> Ecto.Changeset.change(left_at: DateTime.utc_now()) |> Repo.update!()
    assert {:ok, [%{deadline_at: ^deadline}]} = Assignments.list_student_schedule(student)
  end
end
