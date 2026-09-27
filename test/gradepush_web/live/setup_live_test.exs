defmodule GradePushWeb.SetupLiveTest do
  use GradePushWeb.ConnCase, async: true

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias GradePush.Crypto
  alias GradePush.Installation
  alias GradePush.Installation.BootstrapCredential
  alias GradePush.Repo

  test "installed apps return to organization settings without connecting an unverified installation",
       %{
         conn: conn
       } do
    %{user: user} = GradePush.AccountsFixtures.bootstrap_fixture()

    assert {:error, {:redirect, %{to: "/teacher/settings?section=organizations"}}} =
             live(conn, "/setup?installation_id=123&setup_action=install")

    assert GradePush.Classrooms.list_github_connections(user) == {:ok, []}
  end

  test "installation parameters cannot bypass initial setup", %{conn: conn} do
    setup_token()
    {:ok, view, _html} = live(conn, "/setup?installation_id=123&setup_action=install")

    assert has_element?(view, "#setup-form")
    refute Installation.configured?()
  end

  test "valid setup submits only the manifest to GitHub without a second confirmation", %{
    conn: conn
  } do
    token = setup_token()
    {:ok, view, _html} = live(conn, "/setup")

    assert has_element?(view, "#setup-form[phx-hook='SetupToken']")

    assert has_element?(
             view,
             ".cp-setup-token-help code",
             "docker compose exec app gradepush-setup"
           )

    view
    |> form("#setup-form", setup: %{institution_name: "Test College", setup_token: token})
    |> render_submit()

    assert has_element?(view, "#setup-form[phx-trigger-action='true']")
    assert has_element?(view, "#setup-form .cp-setup-progress", "Opening GitHub...")
    assert has_element?(view, "#setup-form input[name='manifest']")
    refute has_element?(view, "#setup-form input[name='setup[institution_name]']")
    refute has_element?(view, "#setup-form input[name='setup[setup_token]']")
    refute has_element?(view, "#setup-form button")
    refute has_element?(view, "#setup-form input[name='_csrf_token']")

    outgoing = follow_trigger_action(form(view, "#setup-form"), conn)

    assert outgoing.method == "POST"
    assert outgoing.request_path == "/settings/apps/new"
    assert Map.keys(outgoing.body_params) == ["manifest"]
    assert Map.keys(outgoing.query_params) == ["state"]
    assert {:ok, manifest} = Jason.decode(outgoing.body_params["manifest"])
    assert manifest["name"] == "GradePush"
    refute outgoing.body_params["manifest"] =~ token
  end

  test "invalid setup token keeps the form available and reports an error", %{conn: conn} do
    setup_token()
    {:ok, view, _html} = live(conn, "/setup")

    view
    |> form("#setup-form", setup: %{institution_name: "Test College", setup_token: "invalid"})
    |> render_submit()

    assert has_element?(view, "[role='alert']", "The setup token is invalid.")
    assert has_element?(view, "#setup-form button", "Create GitHub App")
    refute has_element?(view, "#setup-form[phx-trigger-action]")
    refute Installation.configured?()

    render_hook(view, "invalid_setup_token_link", %{})
    assert has_element?(view, "[role='alert']", "The setup link is invalid or expired.")
  end

  test "public setup page does not expose the bootstrap token", %{conn: conn} do
    token = setup_token()
    conn = get(conn, "/setup")
    html = html_response(conn, 200)

    refute html =~ token
    assert html =~ "One-time setup token"
    assert html =~ "docker compose exec app gradepush-setup"
  end

  defp setup_token do
    capture_log(fn -> assert {:ok, :created} = Installation.initialize_bootstrap() end)
    credential = Repo.get!(BootstrapCredential, 1)
    assert {:ok, token} = Crypto.decrypt(credential.token_encrypted, "bootstrap.token")
    token
  end
end
