defmodule GradePush.AssignmentValidationTest do
  use GradePush.DataCase, async: true, group: :institution

  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures

  alias GradePush.Assignments

  test "explicitly null required settings return errors on creation and update" do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    assignment = assignment_fixture(teacher, classroom)

    for field <- [:team_size, :repository_name_pattern, :cutoff_enabled, :autograding_enabled] do
      attrs = Map.put(%{title: "Invalid settings"}, field, nil)

      assert {:error, changeset} = Assignments.create_assignment(teacher, classroom.id, attrs)
      assert {"can't be blank", _} = changeset.errors[field]

      assert {:error, changeset} = Assignments.update_assignment(teacher, assignment.id, attrs)
      assert {"can't be blank", _} = changeset.errors[field]
    end

    assert {:ok, stored} = Assignments.get_assignment(teacher, classroom.id, assignment.slug)
    assert stored.title == assignment.title
  end

  test "null test timeouts are rejected before persisting an assignment" do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)

    assert {:error, changeset} =
             Assignments.create_assignment(teacher, classroom.id, %{
               title: "Invalid timeout",
               autograding_enabled: true,
               tests: [
                 %{
                   name: "Check",
                   type: "command",
                   command: "true",
                   points: 10,
                   timeout_seconds: nil
                 }
               ]
             })

    assert {"can't be blank", _} = changeset.errors[:timeout_seconds]
    assert {:ok, []} = Assignments.list_assignments(teacher, classroom.id)
  end

  test "enabling autograding requires tests for every accepted boolean representation" do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    assignment = assignment_fixture(teacher, classroom)

    for enabled <- [true, "true", "1"] do
      attrs = %{title: "Missing tests", autograding_enabled: enabled}

      assert {:error, :tests_required} =
               Assignments.create_assignment(teacher, classroom.id, attrs)

      assert {:error, :tests_required} =
               Assignments.update_assignment(teacher, assignment.id, attrs)
    end
  end

  test "test options are persisted and cannot be changed after acceptance" do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)

    spec = %{
      name: "Greeting",
      type: "io",
      command: "python main.py",
      expected: "  Hello world\n",
      points: 10,
      timeout_seconds: 90,
      output_comparison: "exact",
      runtime: "python-3.14.7",
      setup_command: "pip install -r requirements.txt"
    }

    assignment = assignment_fixture(teacher, classroom, autograding_enabled: true, tests: [spec])
    assert {:ok, saved} = Assignments.get_assignment(teacher, classroom.id, assignment.slug)
    [test] = saved.tests
    assert test.setup_command == "pip install -r requirements.txt"

    assert {test.timeout_seconds, test.output_comparison, test.runtime, test.expected} ==
             {90, "exact", "python-3.14.7", "  Hello world\n"}

    student = student_fixture()
    {:ok, invitation} = Assignments.create_assignment_invitation(teacher, assignment.id)
    {:ok, _} = Assignments.accept_assignment_invitation(student, invitation.token, %{})

    for changed <- [
          %{timeout_seconds: 120},
          %{output_comparison: "trim_trailing"},
          %{runtime: "node-24.21.0"},
          %{setup_command: "echo changed"}
        ] do
      assert {:error, :assignment_locked} =
               Assignments.update_assignment(teacher, assignment.id, %{
                 tests: [Map.merge(spec, changed)]
               })
    end

    assert {:ok, unchanged} =
             Assignments.update_assignment(teacher, assignment.id, %{
               title: "Greeting lab",
               tests: [spec]
             })

    assert unchanged.title == "Greeting lab"
  end
end
