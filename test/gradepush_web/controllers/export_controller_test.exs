defmodule GradePushWeb.ExportControllerTest do
  use GradePushWeb.ConnCase, async: true

  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures

  alias GradePush.{Assignments, Classrooms}

  test "only a classroom teacher can export its roster and submissions", %{conn: conn} do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    assignment = assignment_fixture(teacher, classroom)
    student = user_fixture()
    {:ok, invitation} = Classrooms.create_class_invitation(teacher, classroom.id)

    {:ok, _} =
      Classrooms.accept_class_invitation(student, invitation.token, %{
        "name" => "=Unsafe Formula",
        "student_id" => "2026001"
      })

    path = "/classrooms/#{classroom.slug}/assignments/#{assignment.slug}/export.csv"

    exported = conn |> log_in_user(teacher) |> get(path)
    assert response(exported, 200) =~ "'=Unsafe Formula"
    assert exported.resp_body =~ "2026001"
    assert exported.resp_body =~ student.login
    assert get_resp_header(exported, "cache-control") == ["private, no-store"]
    assert get_resp_header(exported, "content-disposition") |> hd() =~ "attachment"

    outsider = user_fixture()
    teacher_membership_fixture(outsider)
    assert conn |> log_in_user(outsider) |> get(path) |> response(404)
    assert conn |> log_in_user(student) |> get(path) |> response(404)
    assert conn |> init_test_session(%{ui_preview: false}) |> get(path) |> response(404)
    assert {:ok, []} = Assignments.list_submissions(teacher, assignment.id)
  end
end
