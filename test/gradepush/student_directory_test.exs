defmodule GradePush.StudentDirectoryTest do
  use GradePush.DataCase, async: true

  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures
  alias GradePush.{Accounts, Assignments, Classrooms}

  alias GradePush.Accounts.InstitutionMembership
  alias GradePush.Assignments.Repository
  alias GradePush.Classrooms.ClassroomStudent

  test "removal revokes all student classroom access, keeps work and allows an explicit rejoin" do
    %{user: admin} = bootstrap_fixture()
    student = student_fixture()
    teacher = user_fixture()
    teacher_membership_fixture(teacher)
    operator = user_fixture()
    {:ok, _} = Accounts.grant_platform_operator(admin, operator.id)
    classroom = classroom_fixture(admin)
    other = classroom_fixture(admin)
    assignment = assignment_fixture(admin, classroom)
    {:ok, invite} = Assignments.create_assignment_invitation(admin, assignment.id)
    {:ok, accepted} = Assignments.accept_assignment_invitation(student, invite.token, %{})
    {:ok, class_invite} = Classrooms.create_class_invitation(admin, other.id)
    {:ok, _} = Classrooms.accept_class_invitation(student, class_invite.token, %{})
    Phoenix.PubSub.subscribe(GradePush.PubSub, "user:#{student.id}")

    for actor <- [student, teacher, operator, nil] do
      assert {:error, :unauthorized} = Accounts.remove_student(actor, student.id)
    end

    assert {:error, :not_found} = Accounts.remove_student(admin, "invalid")
    assert {:error, :cannot_remove_self} = Accounts.remove_student(admin, admin.id)
    assert {:ok, :removed} = Accounts.remove_student(admin, to_string(student.id))
    assert_receive {:student_removed, id}
    assert id == student.id
    refute Accounts.student?(student)
    assert Accounts.get_user(student.id)
    assert Repo.get!(Repository, accepted.repository.id) == accepted.repository
    assert {:error, _} = Classrooms.get_student_classroom(student, classroom.slug)

    assert Repo.aggregate(
             from(s in ClassroomStudent,
               where: s.user_id == ^student.id and is_nil(s.removed_at)
             ),
             :count
           ) == 0

    assert {:ok, %{total: 0}} = Accounts.list_institution_students(admin)
    assert {:error, :not_found} = Accounts.remove_student(admin, student.id)
    assert {:ok, events} = Accounts.list_audit(admin, :institution)
    assert Enum.count(events, &(&1.action == "student.removed")) == 1

    assert {:ok, rejoined} =
             Assignments.accept_assignment_invitation(student, invite.token, %{
               name: "Returning student",
               student_id: "R-1"
             })

    assert rejoined.repository.id == accepted.repository.id
    assert rejoined.subject.id == accepted.subject.id
    assert {:ok, _} = Classrooms.get_student_classroom(student, classroom.slug)
    assert {:error, _} = Classrooms.get_student_classroom(student, other.slug)
  end

  test "student removal keeps independent teacher and platform roles" do
    %{user: admin} = bootstrap_fixture()
    student = student_fixture()
    teacher_membership_fixture(student)
    {:ok, _} = Accounts.grant_platform_operator(admin, student.id)
    assert {:ok, :removed} = Accounts.remove_student(admin, student.id)
    assert Accounts.teacher?(student)
    assert Accounts.operator?(student)
  end

  test "only institution admins see completed profiles and active enrollment counts" do
    %{user: admin} = bootstrap_fixture()
    student = student_fixture(%{student_name: "Alice Martin", student_id: "ST-101"})
    incomplete = student_fixture()

    Repo.update_all(from(m in InstitutionMembership, where: m.user_id == ^incomplete.id),
      set: [student_name: nil]
    )

    user_fixture(%{login: "signed-in-only"})
    teacher = user_fixture()
    teacher_membership_fixture(teacher)
    operator = user_fixture()
    {:ok, _} = Accounts.grant_platform_operator(admin, operator.id)
    now = DateTime.utc_now()

    for removed_at <- [nil, nil, now] do
      classroom = classroom_fixture(admin)

      Repo.insert!(%ClassroomStudent{
        classroom_id: classroom.id,
        user_id: student.id,
        joined_at: now,
        removed_at: removed_at
      })
    end

    assert {:ok, %{entries: [entry], total: 1}} = Accounts.list_institution_students(admin)
    assert entry.name == "Alice Martin"
    assert entry.identifier == "ST-101"
    assert entry.classrooms == 2

    assert Map.keys(entry) |> Enum.sort() == [
             :avatar_url,
             :classrooms,
             :handle,
             :id,
             :identifier,
             :name
           ]

    for actor <- [teacher, student, operator, nil] do
      assert {:error, :unauthorized} = Accounts.list_institution_students(actor)
    end
  end

  test "search is literal and case insensitive with stable bounded pagination" do
    %{user: admin} = bootstrap_fixture()

    students =
      for n <- 1..27 do
        suffix = n |> to_string() |> String.pad_leading(2, "0")

        student_fixture(%{
          student_name: "Student #{suffix}",
          student_id: "ID_#{suffix}",
          login: "learner-#{suffix}"
        })
      end

    assert {:ok, %{entries: first, page: 1, pages: 2, total: 27}} =
             Accounts.list_institution_students(admin)

    assert length(first) == 25

    assert {:ok, %{entries: last, page: 2}} =
             Accounts.list_institution_students(admin, page: "999")

    assert Enum.map(first ++ last, & &1.id) == Enum.map(students, & &1.id)
    assert {:ok, %{page: 1}} = Accounts.list_institution_students(admin, page: "bad")

    for query <- ["student 27", "ID_27", "LEARNER-27"] do
      assert {:ok, %{entries: [entry], total: 1, page: 1}} =
               Accounts.list_institution_students(admin, query: query, page: 2)

      assert entry.id == List.last(students).id
    end

    assert {:ok, %{entries: [], total: 0}} = Accounts.list_institution_students(admin, query: "%")
  end
end
