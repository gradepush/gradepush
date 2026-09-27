defmodule GradePushWeb.Preview.AdministrationTest do
  use ExUnit.Case, async: true
  alias GradePushWeb.Preview.Administration

  test "staffing rejects self-assignment, unknown members and invalid replacements" do
    state = Administration.initial()

    for params <- [
          %{"teacher" => "jordan"},
          %{"teacher" => "unknown"},
          %{"teacher" => "sophie", "replace" => "camille"}
        ] do
      assert {:error, _} = Administration.change_staff(state, "jordan", "databases", params)
    end

    assert {:error, _} =
             Administration.change_staff(state, "jordan", "unknown", %{"teacher" => "sophie"})

    assert {:ok, updated} =
             Administration.change_staff(state, "jordan", "databases", %{
               "teacher" => "sophie",
               "replace" => "alex"
             })

    assert Administration.classroom(updated, "databases").teachers == ["sophie"]
  end

  test "the last administrator and teachers assigned to classes cannot be removed" do
    state = Administration.initial()
    assert {:ok, state} = Administration.change_role(state, "jordan", "camille", "teacher")
    assert {:error, _} = Administration.change_role(state, "jordan", "jordan", "teacher")
    assert {:error, _} = Administration.remove_teacher(state, "jordan", "jordan")
    assert {:error, _} = Administration.remove_teacher(state, "jordan", "alex")
    assert {:ok, updated} = Administration.remove_teacher(state, "jordan", "sophie")
    assert updated.classrooms == state.classrooms
    assert length(updated.history) == length(state.history) + 1
  end
end
