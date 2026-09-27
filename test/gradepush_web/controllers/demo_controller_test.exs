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
