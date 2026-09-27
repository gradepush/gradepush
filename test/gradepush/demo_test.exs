defmodule GradePush.DemoTest do
  use GradePush.DataCase, async: false

  alias GradePush.Accounts
  alias GradePush.Accounts.{Institution, User}
  alias GradePush.Assignments
  alias GradePush.Assignments.{Assignment, Repository, Subject}
  alias GradePush.Classrooms
  alias GradePush.Classrooms.Classroom
  alias GradePush.Demo
  alias GradePush.GitHub.Fake
  alias GradePush.GitHub.Fake.Store
  alias GradePush.Repo
  alias GradePush.Workers.ProvisionAssignmentRepository

  setup do
    original = Application.get_env(:gradepush, :demo_mode, false)
    on_exit(fn -> Application.put_env(:gradepush, :demo_mode, original) end)
    :ok
  end

  test "claims an empty database once and seeds usable teacher and student accounts" do
    Application.put_env(:gradepush, :demo_mode, true)

    assert :ok = Demo.initialize()
    assert :demo = Demo.mode()
    assert :ok = Demo.initialize()

    assert %Institution{name: "Cégep de Sorel-Tracy"} = Accounts.institution()
    assert {:ok, %User{login: "demo-teacher"} = teacher} = Demo.user_for_role(:teacher)
    assert Accounts.admin?(teacher)
    assert Accounts.teacher?(teacher)
    assert Accounts.operator?(teacher)
    assert {:ok, %User{login: "amelie-fortin"} = student} = Demo.user_for_role(:student)
    assert Accounts.student?(student)
    assert student.student_id == "D-1001"

    assert {:ok, classrooms} = Classrooms.list_classrooms(teacher)

    assert MapSet.new(Enum.map(classrooms, & &1.slug)) ==
             MapSet.new(["programming", "web-development"])

    assert Enum.all?(classrooms, &(&1.students_count > 0 and &1.assignments_count > 0))

    {:ok, programming} = Classrooms.get_student_classroom(student, "programming")
    assert {:ok, assignments} = Assignments.list_student_assignments(student, programming.id)
    assert Enum.map(assignments, & &1.assignment.slug) == ["loops", "cli", "functions"]
    assert Enum.any?(assignments, &match?(%{repository: %{state: "ready"}}, &1))

    {:ok, %{repository: repository}} =
      Assignments.get_student_assignment(student, programming.id, "cli")

    assert Store.get({:repository, repository.owner_login, repository.name})["id"] ==
             repository.github_repository_id
  end

  test "seeded assignment template remains valid when editing its title" do
    Application.put_env(:gradepush, :demo_mode, true)
    assert :ok = Demo.initialize()
    {:ok, teacher} = Demo.user_for_role(:teacher)
    {:ok, classroom} = Classrooms.get_classroom(teacher, "programming")
    {:ok, assignment} = Assignments.get_assignment(teacher, classroom.id, "cli")

    assert {:ok, %{title: "Revised demo assignment"}} =
             Assignments.update_assignment(teacher, assignment.id, %{
               title: "Revised demo assignment"
             })
  end

  test "refuses demo mode when a self-hosted installation contains real records" do
    Application.put_env(:gradepush, :demo_mode, false)
    assert :ok = Demo.initialize()

    %User{}
    |> User.changeset(%{
      github_id: 8_765_432,
      login: "existing-teacher",
      name: "Existing Teacher"
    })
    |> Repo.insert!()

    Application.put_env(:gradepush, :demo_mode, true)

    assert {:error, :demo_requires_empty_installation} = Demo.initialize()
    assert :self_hosted = Demo.mode()
    assert Repo.get_by(User, login: "demo-teacher") == nil
  end

  test "refuses to boot a persisted demo database as a real installation" do
    Application.put_env(:gradepush, :demo_mode, true)
    assert :ok = Demo.initialize()

    Application.put_env(:gradepush, :demo_mode, false)

    assert {:error, :demo_database_requires_demo_mode} = Demo.initialize()
    assert :demo = Demo.mode()
    assert Repo.get_by(User, login: "demo-teacher")
  end

  test "reset is demo-only, disconnects old sessions, and leaves the marker and new ids intact" do
    Application.put_env(:gradepush, :demo_mode, true)
    assert :ok = Demo.initialize()
    assert {:ok, teacher} = Demo.user_for_role(:teacher)
    assert {:ok, token} = Accounts.create_session(teacher)
    assert {:ok, _expiry} = Accounts.watch_session(token)
    Store.put({:repository, "gradepush-demo", "visitor-created"}, %{"id" => 55})

    assert :ok = Demo.reset()
    assert Store.get({:repository, "gradepush-demo", "visitor-created"}) == nil

    assert {:ok, _created_repository} =
             Fake.create_repository("test-token", "gradepush-demo", %{
               repository_name: "visitor-created"
             })

    assert_receive :gradepush_session_revoked
    assert Accounts.get_user_by_session_token(token) == nil
    assert :demo = Demo.mode()
    assert {:ok, %User{id: new_teacher_id} = new_teacher} = Demo.user_for_role(:teacher)
    assert new_teacher_id != teacher.id

    {:ok, %Classroom{} = programming} =
      Classrooms.get_classroom(new_teacher, "programming")

    {:ok, new_student} = Demo.user_for_role(:student)

    {:ok, %{repository: repository}} =
      Assignments.get_student_assignment(new_student, programming.id, "cli")

    assert Store.get({:repository, repository.owner_login, repository.name})["id"] ==
             repository.github_repository_id

    Application.put_env(:gradepush, :demo_mode, false)
    assert {:error, :demo_mode_disabled} = Demo.reset()
    assert :demo = Demo.mode()
  end

  test "startup rehydrates persisted repository identities regardless of state" do
    Application.put_env(:gradepush, :demo_mode, true)
    assert :ok = Demo.initialize()
    {:ok, teacher} = Demo.user_for_role(:teacher)
    {:ok, student} = Demo.user_for_role(:student)
    {:ok, classroom} = Classrooms.get_classroom(teacher, "programming")

    {:ok, %{subject: subject, repository: repository}} =
      Assignments.get_student_assignment(student, classroom.id, "loops")

    {:ok, _repository} =
      repository
      |> Repository.changeset(%{state: "pending"})
      |> Repo.update()

    assignment = Repo.get_by!(Assignment, classroom_id: classroom.id, slug: "loops")
    unaccepted_student = Repo.get_by!(User, login: "emile-tremblay")

    unprovisioned_subject =
      %Subject{}
      |> Subject.changeset(%{
        assignment_id: assignment.id,
        user_id: unaccepted_student.id,
        kind: "individual",
        accepted_at: DateTime.utc_now()
      })
      |> Repo.insert!()

    %Repository{subject_id: unprovisioned_subject.id}
    |> Repository.changeset(%{
      owner_login: "gradepush-demo",
      name: "not-created-yet",
      state: "pending"
    })
    |> Repo.insert!()

    Fake.reset!()

    assert :ok = Demo.initialize()

    assert Store.get({:repository, repository.owner_login, repository.name})["id"] ==
             repository.github_repository_id

    assert Store.get({:repository, "gradepush-demo", "not-created-yet"}) == nil

    assert :ok =
             ProvisionAssignmentRepository.perform(%Oban.Job{
               args: %{"subject_id" => subject.id},
               attempt: 2,
               max_attempts: 10
             })
  end

  test "demo invitations are blocked only when demo mode is enabled" do
    Application.put_env(:gradepush, :demo_mode, false)
    assert :ok = Demo.ensure_invitations_enabled()

    Application.put_env(:gradepush, :demo_mode, true)
    assert {:error, :demo_invitations_disabled} = Demo.ensure_invitations_enabled()
  end
end
