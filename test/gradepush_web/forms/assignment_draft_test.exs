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
end
