defmodule GradePushWeb.AuthControllerTest do
  use GradePushWeb.ConnCase, async: true, group: :institution

  import GradePush.AccountsFixtures, only: [configured_gradepush_fixture: 0]

  alias GradePush.Accounts

  test "OAuth state is one-time and successful sign-in rotates the session", %{conn: conn} do
    configured_gradepush_fixture()

    conn =
      conn
      |> init_test_session(%{return_to: "/student/classrooms?sort=due", stale_marker: "discard"})
      |> get("/auth/github")

    state = get_session(conn, :oauth_state)
    assert is_binary(state)
    assert get_session(conn, :oauth_state_issued_at)
    assert [location] = get_resp_header(conn, "location")
    assert location =~ "https://github.com/login/oauth/authorize"

    callback_path =
      "/auth/github/callback?" <> URI.encode_query(%{code: "fake-code", state: state})

    conn = recycle(conn) |> get(callback_path)

    assert redirected_to(conn) == "/student/classrooms?sort=due"
    assert is_nil(get_session(conn, :oauth_state))
    assert is_nil(get_session(conn, :oauth_state_issued_at))
    assert is_nil(get_session(conn, :return_to))
    assert is_nil(get_session(conn, :stale_marker))

    token = get_session(conn, :user_token)
    assert Accounts.get_user_by_session_token(token).github_id == 234

    conn = recycle(conn) |> get(callback_path)
    assert redirected_to(conn) == "/auth/sign-in"
    assert get_session(conn, :user_token) == token

    conn = recycle(conn) |> delete("/auth/logout")
    assert redirected_to(conn) == "/auth/sign-in"
    assert is_nil(Accounts.get_user_by_session_token(token))
  end

  test "OAuth callback rejects a mismatched or expired state", %{conn: conn} do
    configured_gradepush_fixture()

    conn = get(conn, "/auth/github")
    state = get_session(conn, :oauth_state)

    conn =
      recycle(conn)
      |> get(
        "/auth/github/callback?" <> URI.encode_query(%{code: "fake-code", state: "wrong-state"})
      )

    assert redirected_to(conn) == "/auth/sign-in"
    assert is_nil(get_session(conn, :user_token))

    expired_session = %{
      "oauth_state" => state,
      "oauth_state_issued_at" => System.system_time(:second) - 601
    }

    conn =
      build_conn()
      |> init_test_session(expired_session)
      |> get("/auth/github/callback?" <> URI.encode_query(%{code: "fake-code", state: state}))

    assert redirected_to(conn) == "/auth/sign-in"
    assert is_nil(get_session(conn, :user_token))
  end
end
