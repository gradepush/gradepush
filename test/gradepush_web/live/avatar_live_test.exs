defmodule GradePushWeb.AvatarLiveTest do
  use GradePushWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures

  alias GradePush.{Assignments, Classrooms}

  setup do
    %{user: teacher} =
      bootstrap_fixture(%{avatar_url: "https://avatars.githubusercontent.com/u/101"})

    student = student_fixture(%{avatar_url: "https://avatars.githubusercontent.com/u/102"})
    classroom = classroom_fixture(teacher)
    {:ok, invitation} = Classrooms.create_class_invitation(teacher, classroom.id)
    {:ok, _} = Classrooms.accept_class_invitation(student, invitation.token, %{})
    %{teacher: teacher, student: student, classroom: classroom}
  end

  test "institution teachers and their management dialog render stored profile photos", %{
    conn: conn,
    teacher: teacher
  } do
    conn = log_in_user(conn, teacher)
    {:ok, view, _} = live(conn, "/admin/institution?section=teachers")
    assert has_element?(view, "tbody img[data-avatar][src='#{teacher.avatar_url}']")
    view |> element("button[aria-label='Manage #{teacher.name}']") |> render_click()
    assert has_element?(view, "#admin-dialog img[data-avatar][src='#{teacher.avatar_url}']")
  end

  test "class cards, rosters, colleagues and team members keep avatars in both perspectives", %{
    conn: conn,
    teacher: teacher,
    student: student,
    classroom: classroom
  } do
    teacher_conn = log_in_user(conn, teacher)
    {:ok, view, _} = live(teacher_conn, "/classrooms")
    assert has_element?(view, "[data-ui=card-teachers] img[src='#{teacher.avatar_url}']")

    {:ok, view, _} = live(teacher_conn, "/classrooms/#{classroom.slug}?tab=students")
    assert has_element?(view, "#student-#{student.login} img[src='#{student.avatar_url}']")
    view |> element("button", "Manage teachers") |> render_click()
    assert has_element?(view, "[data-ui=teacher-list] img[src='#{teacher.avatar_url}']")

    assignment = assignment_fixture(teacher, classroom, %{kind: "team", team_mode: "teacher"})
    {:ok, team} = Assignments.create_team(teacher, assignment.id, %{name: "Team One"})
    {:ok, _} = Assignments.add_team_member(teacher, assignment.id, team.id, student.id)

    {:ok, view, _} =
      live(teacher_conn, "/classrooms/#{classroom.slug}/assignments/#{assignment.slug}")

    view |> element("button", "Manage teams") |> render_click()
    assert has_element?(view, "#managed-team-#{team.id} img[src='#{student.avatar_url}']")

    {:ok, view, _} = conn |> log_in_user(student) |> live("/student/classrooms")
    assert has_element?(view, "[data-ui=card-teachers] img[src='#{teacher.avatar_url}']")
    assert has_element?(view, "[data-ui=profile-identity] img[src='#{student.avatar_url}']")
  end
end
