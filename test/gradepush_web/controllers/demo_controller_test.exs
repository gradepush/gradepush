defmodule GradePushWeb.DemoControllerTest do
  use GradePushWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias GradePush.Accounts
  alias GradePush.Demo

  setup do
    original = Application.get_env(:gradepush, :demo_mode, false)
    Application.put_env(:gradepush, :demo_mode, true)
    assert :ok = Demo.initialize()
    on_exit(fn -> Application.put_env(:gradepush, :demo_mode, original) end)
    :ok
  end

  test "sharing opens the demo dialog without creating a usable invitation", %{conn: conn} do
    teacher = GradePush.Repo.get_by!(Accounts.User, login: "demo-teacher")

    {:ok, view, _} =
      conn |> log_in_user(teacher) |> live("/classrooms/programming/assignments/cli")

    before_count = GradePush.Repo.aggregate(GradePush.Assignments.Invitation, :count)
    view |> element("button", "Share assignment") |> render_click()
    assert has_element?(view, "#assignment-invitation-input[disabled][value='']")
    assert has_element?(view, "#assignment-invitation-copy[disabled]")
    assert GradePush.Repo.aggregate(GradePush.Assignments.Invitation, :count) == before_count
    view |> element(".cp-modal-actions button", "Close") |> render_click()
    view |> element("button", "Clone all locally") |> render_click()

    assert has_element?(
             view,
             "[role='dialog']",
             "Bulk cloning and this command are not available yet"
           )

    assert has_element?(view, "[role='dialog'] code", "gh gradepush clone --assignment cli")
  end

  test "the demo page signs in the selected role through a revocable session", %{conn: conn} do
    {:ok, view, html} = live(conn, "/demo")
    assert html =~ "Continue as a teacher"
    assert html =~ "Continue as a student"

    assert has_element?(view, "form[action='/demo/sign-in'] input[name='_csrf_token']")
    [_, csrf_token] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, html)

    conn =
      post(conn, "/demo/sign-in", %{
        "role" => "student",
        "locale" => "en",
        "_csrf_token" => csrf_token
      })

    assert redirected_to(conn) == "/student/classrooms"
    assert get_session(conn, :locale) == "en"

    assert %Accounts.User{login: "amelie-fortin"} =
             Accounts.get_user_by_session_token(get_session(conn, :user_token))
  end

  test "role input is allow-listed", %{conn: conn} do
    conn = post(conn, "/demo/sign-in", %{"role" => "operator"})
    assert redirected_to(conn) == "/demo"
    assert is_nil(get_session(conn, :user_token))
  end
end
