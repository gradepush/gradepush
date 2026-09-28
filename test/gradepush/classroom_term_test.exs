defmodule GradePush.ClassroomTermTest do
  use GradePush.DataCase, async: true

  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures

  alias GradePush.Classrooms

  test "classrooms persist a structured semester and year" do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher, %{semester: "summer", academic_year: "2027"})

    assert classroom.semester == :summer
    assert classroom.academic_year == "2027"

    assert {:ok, updated} =
             Classrooms.update_classroom(teacher, classroom.id, %{
               title: classroom.title,
               semester: "winter",
               academic_year: "2028"
             })

    assert updated.semester == :winter
    assert updated.academic_year == "2028"
    assert updated.code == classroom.code
  end

  test "unassigned terms are valid and partial terms are rejected" do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)

    assert {:ok, unassigned} =
             Classrooms.update_classroom(teacher, classroom.id, %{
               title: classroom.title,
               semester: "",
               academic_year: ""
             })

    assert is_nil(unassigned.semester)
    assert is_nil(unassigned.academic_year)

    assert {:error, changeset} =
             Classrooms.create_classroom(teacher, %{
               title: "Incomplete term",
               github_connection_id: classroom.github_connection_id,
               semester: "fall"
             })

    assert Keyword.has_key?(changeset.errors, :academic_year)
  end

  test "academic year labels are preserved and limited to twenty characters" do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)

    assert {:ok, updated} =
             Classrooms.update_classroom(teacher, classroom.id, %{
               title: classroom.title,
               semester: "fall",
               academic_year: "26"
             })

    assert updated.academic_year == "26"

    assert {:ok, labeled} =
             Classrooms.update_classroom(teacher, classroom.id, %{
               title: classroom.title,
               semester: "fall",
               academic_year: "2026-2027"
             })

    assert labeled.academic_year == "2026-2027"

    assert {:error, year_changeset} =
             Classrooms.update_classroom(teacher, classroom.id, %{
               title: classroom.title,
               semester: "fall",
               academic_year: String.duplicate("2", 21)
             })

    assert Keyword.has_key?(year_changeset.errors, :academic_year)
  end

  test "unknown semesters are rejected" do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)

    assert {:error, semester_changeset} =
             Classrooms.update_classroom(teacher, classroom.id, %{
               title: classroom.title,
               semester: "spring",
               academic_year: "2027"
             })

    assert Keyword.has_key?(semester_changeset.errors, :semester)
  end

  test "updates without term fields preserve the selected term" do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher, %{semester: :fall, academic_year: "26"})

    assert {:ok, updated} =
             Classrooms.update_classroom(teacher, classroom.id, %{title: "Evening cohort"})

    assert updated.semester == :fall
    assert updated.academic_year == "26"
  end

  test "semester identifiers are persisted as integers" do
    %{user: teacher} = bootstrap_fixture()

    for {semester, id} <- [winter: 1, summer: 2, fall: 3] do
      classroom = classroom_fixture(teacher, %{semester: semester, academic_year: "26"})

      assert [[^id, "text"]] =
               Repo.query!(
                 "SELECT semester, pg_typeof(academic_year)::text FROM classrooms WHERE id = $1",
                 [classroom.id]
               ).rows
    end
  end

  test "the database rejects invalid identifiers and incomplete terms" do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)

    for semester <- [0, 4, nil] do
      assert_raise Postgrex.Error, ~r/classroom_term_check/, fn ->
        Repo.query!("UPDATE classrooms SET semester = $1 WHERE id = $2", [semester, classroom.id],
          mode: :savepoint
        )
      end
    end
  end
end
