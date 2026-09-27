defmodule GradePush.ClassroomTest do
  use ExUnit.Case, async: true

  alias GradePush.Classrooms.Classroom

  test "course codes are required for new classrooms and cannot be cleared on edit" do
    attrs = %{title: "Programming", github_connection_id: 1}

    for code <- [nil, "", "   "] do
      changeset = Classroom.changeset(%Classroom{}, Map.put(attrs, :code, code))
      assert Keyword.has_key?(changeset.errors, :code)

      existing = struct!(Classroom, Map.put(attrs, :code, "420-110"))
      changeset = Classroom.changeset(existing, %{code: code})
      assert Keyword.has_key?(changeset.errors, :code)
    end

    assert Keyword.has_key?(Classroom.changeset(%Classroom{}, attrs).errors, :code)

    changeset = Classroom.changeset(%Classroom{}, Map.put(attrs, :code, " 420-110 "))
    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :code) == "420-110"
  end
end
