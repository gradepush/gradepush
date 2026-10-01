defmodule GradePushWeb.Forms.AssignmentDraftTest do
  use ExUnit.Case, async: true
  alias GradePushWeb.Forms.AssignmentDraft

  test "deadline and enabled tests are validated, with no cutoff without a date" do
    changeset =
      AssignmentDraft.changeset(%AssignmentDraft{}, %{"title" => "Lab", "cutoff" => "true"}, [])

    assert changeset.valid?
    refute Ecto.Changeset.get_field(changeset, :cutoff)

    invalid =
      AssignmentDraft.changeset(
        %AssignmentDraft{},
        %{"title" => "Lab", "deadline" => "invalid", "autograding" => "true"},
        []
      )

    assert Keyword.has_key?(invalid.errors, :deadline)
    assert Keyword.has_key?(invalid.errors, :autograding)
  end

  test "each test requires its relevant inputs and positive points" do
    for {type, missing} <- [{"file", :path}, {"command", :command}, {"io", :expected}] do
      params = %{
        "title" => "Lab",
        "autograding" => "true",
        "tests" => [%{"name" => "Test", "type" => type, "points" => "0"}]
      }

      changeset = AssignmentDraft.changeset(%AssignmentDraft{}, params, [])
      refute changeset.valid?
      [test] = Ecto.Changeset.get_change(changeset, :tests)
      assert Keyword.has_key?(test.errors, missing)
      assert Keyword.has_key?(test.errors, :points)
    end
  end

  test "disabling tests clears incomplete test definitions" do
    params = %{"title" => "Lab", "autograding" => "false", "tests" => [%{"name" => ""}]}
    changeset = AssignmentDraft.changeset(%AssignmentDraft{}, params, [])
    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :tests) == []
  end

  test "the assignment form rejects a null team size" do
    changeset =
      AssignmentDraft.changeset(
        %AssignmentDraft{},
        %{title: "Team project", kind: "team", team_size: nil},
        []
      )

    assert {"can't be blank", _} = changeset.errors[:team_size]
  end

  test "new test defaults and selected options survive the form, with invalid limits rejected" do
    params = %{
      "title" => "Lab",
      "autograding" => "true",
      "tests" => [
        %{
          "name" => "Greeting",
          "type" => "io",
          "command" => "python main.py",
          "expected" => "  Hello world\n"
        }
      ]
    }

    changeset = AssignmentDraft.changeset(%AssignmentDraft{}, params, [])
    assert changeset.valid?
    [test] = Ecto.Changeset.apply_changes(changeset).tests
    assert test.output_comparison == "trim_trailing"
    assert test.runtime == "system"
    assert test.setup_command == ""
    assert test.timeout_seconds == 300
    assert test.expected == "  Hello world\n"

    selected =
      Map.merge(hd(params["tests"]), %{
        "output_comparison" => "exact",
        "runtime" => "python-3.14.7",
        "timeout_seconds" => "90",
        "setup_command" => "pip install -r requirements.txt"
      })

    chosen =
      AssignmentDraft.changeset(%AssignmentDraft{}, Map.put(params, "tests", [selected]), [])

    assert chosen.valid?
    [test] = Ecto.Changeset.apply_changes(chosen).tests
    assert test.setup_command == "pip install -r requirements.txt"

    assert {test.output_comparison, test.runtime, test.timeout_seconds} ==
             {"exact", "python-3.14.7", 90}

    for seconds <- [nil, "29", "1201"] do
      invalid =
        AssignmentDraft.changeset(
          %AssignmentDraft{},
          Map.put(params, "tests", [Map.put(selected, "timeout_seconds", seconds)]),
          []
        )

      refute invalid.valid?
      [test] = Ecto.Changeset.get_change(invalid, :tests)
      assert Keyword.has_key?(test.errors, :timeout_seconds)
    end
  end

  test "regex and runtime rules are enforced before saving, including UTF-8 byte limits" do
    spec = %{
      "name" => "Pattern",
      "type" => "io",
      "command" => "python main.py",
      "expected" => "^value: [0-9]+$",
      "output_comparison" => "regex",
      "runtime" => "java-25"
    }

    params = %{"title" => "Lab", "autograding" => "true", "tests" => [spec]}
    assert AssignmentDraft.changeset(%AssignmentDraft{}, params, []).valid?

    for {field, value, error_field} <- [
          {"expected", String.duplicate("é", 2049), :expected},
          {"output_comparison", "eval", :output_comparison},
          {"runtime", "legacy", :runtime},
          {"runtime", "java-99", :runtime}
        ] do
      changeset =
        AssignmentDraft.changeset(
          %AssignmentDraft{},
          Map.put(params, "tests", [Map.put(spec, field, value)]),
          []
        )

      refute changeset.valid?
      [test] = Ecto.Changeset.get_change(changeset, :tests)
      assert Keyword.has_key?(test.errors, error_field)
    end
  end
end
