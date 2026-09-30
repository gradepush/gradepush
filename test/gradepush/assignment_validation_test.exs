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
end
