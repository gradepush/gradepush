defmodule GradePushWeb.CLICloneLiveTest do
  use GradePushWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures

  test "classroom and assignment dialogs use the matching repository scope", %{conn: conn} do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    assignment = assignment_fixture(teacher, classroom)
    conn = log_in_user(conn, teacher)

    {:ok, view, _} = live(conn, "/classrooms/#{classroom.slug}")
    view |> element("button", "Clone all locally") |> render_click()
    assert has_element?(view, "#cli-clone code", "--classroom #{classroom.slug}")
    refute has_element?(view, "#cli-clone code", "--assignment")
    assert has_element?(view, "#cli-login code", GradePushWeb.Endpoint.url())

    {:ok, view, _} =
      live(conn, "/classrooms/#{classroom.slug}/assignments/#{assignment.slug}")

    view |> element("button", "Clone all locally") |> render_click()
    assert has_element?(view, "#cli-clone code", "--assignment #{assignment.slug}")
    assert has_element?(view, "#cli-clone button[aria-label='Copy command']")
    refute has_element?(view, "[role=dialog]", "unavailable in demo mode")
  end
end
