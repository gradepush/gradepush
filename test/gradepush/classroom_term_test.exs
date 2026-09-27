defmodule GradePush.ClassroomTermTest do
  use GradePush.DataCase, async: true

  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures

  alias GradePush.Classrooms

  test "classrooms persist a structured semester and year" do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher, %{semester: "summer", academic_year: "2027"})

    assert classroom.semester == "summer"
    assert classroom.academic_year == "2027"
    assert classroom.session == ""

    assert {:ok, updated} =
             Classrooms.update_classroom(teacher, classroom.id, %{
               title: classroom.title,
               semester: "winter",
               academic_year: "2028"
             })

    assert updated.semester == "winter"
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
    assert unassigned.session == ""

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

  test "legacy session text survives updates that omit structured term fields" do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher, %{session: "Cohorte soir 2027–2028"})

    assert is_nil(classroom.semester)
    assert classroom.session == "Cohorte soir 2027–2028"

    assert {:ok, updated} =
             Classrooms.update_classroom(teacher, classroom.id, %{
               title: "Evening cohort",
               code: classroom.code,
               description: classroom.description
             })

    assert updated.session == "Cohorte soir 2027–2028"
    assert is_nil(updated.semester)
    assert is_nil(updated.academic_year)
  end
end
