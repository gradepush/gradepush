defmodule GradePushWeb.SetupControllerTest do
  use GradePushWeb.ConnCase, async: true, group: :institution

  import ExUnit.CaptureLog

  alias GradePush.Accounts
  alias GradePush.Crypto
  alias GradePush.Installation
  alias GradePush.Installation.BootstrapCredential
  alias GradePush.Repo

  test "manifest and authorization callbacks are bound to the browser that started setup", %{
    conn: conn
  } do
    setup_token = bootstrap_token()
    browser_nonce = nonce()
    other_nonce = nonce()

    assert {:ok, %{state: manifest_state}} =
             Installation.begin_setup(
               setup_token,
               "Test Institution",
               "https://gradepush.example",
               browser_nonce
             )

    wrong_manifest_conn =
      conn
      |> init_test_session(%{setup_browser_nonce: other_nonce})
      |> get(callback_path("/setup/github/manifest/callback", "manifest-code", manifest_state))

    assert redirected_to(wrong_manifest_conn) == "/setup"
    assert Installation.configured?() == false

    manifest_conn =
      build_conn()
      |> init_test_session(%{setup_browser_nonce: browser_nonce, stale_marker: "discard"})
      |> get(callback_path("/setup/github/manifest/callback", "manifest-code", manifest_state))

    assert [authorization_url] = get_resp_header(manifest_conn, "location")
    assert authorization_url =~ "https://github.com/login/oauth/authorize"

    authorization_state =
      authorization_url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    oauth_state = authorization_state["state"]
    assert is_binary(oauth_state)

    wrong_auth_conn =
      build_conn()
      |> init_test_session(%{setup_browser_nonce: other_nonce})
      |> get(callback_path("/setup/github/auth/callback", "oauth-code", oauth_state))

    assert redirected_to(wrong_auth_conn) == "/setup"
    assert Installation.configured?() == false

    auth_conn =
      recycle(manifest_conn)
      |> get(callback_path("/setup/github/auth/callback", "oauth-code", oauth_state))

    assert redirected_to(auth_conn) == "/admin/platform"
    assert is_nil(get_session(auth_conn, :stale_marker))

    session_token = get_session(auth_conn, :user_token)
    administrator = Accounts.get_user_by_session_token(session_token)
    assert Accounts.admin?(administrator)
    assert Accounts.teacher?(administrator)
    assert Accounts.operator?(administrator)

    assert Installation.configured?()

    replay_conn =
      recycle(auth_conn)
      |> get(callback_path("/setup/github/auth/callback", "oauth-code", oauth_state))

    assert redirected_to(replay_conn) == "/setup"
    assert get_session(replay_conn, :user_token) == session_token

    assert is_nil(Repo.get(BootstrapCredential, 1))
  end

  defp bootstrap_token do
    capture_log(fn ->
      assert {:ok, :created} = Installation.initialize_bootstrap()
    end)

    credential = Repo.get!(BootstrapCredential, 1)
    assert {:ok, token} = Crypto.decrypt(credential.token_encrypted, "bootstrap.token")
    token
  end

  defp nonce, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

  defp callback_path(path, code, state),
    do: path <> "?" <> URI.encode_query(%{code: code, state: state})
end
