defmodule GradePushWeb.SetupLiveTest do
  use GradePushWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias GradePush.Crypto
  alias GradePush.Installation
  alias GradePush.Installation.BootstrapCredential
  alias GradePush.Repo
  alias GradePushWeb.Endpoint

  setup %{conn: conn} do
    original = for {key, value} <- :ets.tab2list(Endpoint), do: {key, value}
    set_endpoint_url(original, "grades.example")
    on_exit(fn -> Endpoint.config_change([{Endpoint, original}], []) end)
    {:ok, conn: put_req_header(conn, "x-forwarded-proto", "https"), endpoint_config: original}
  end

  test "localhost setup reports an invalid public URL only when submitted", %{
    conn: conn,
    endpoint_config: config
  } do
    set_endpoint_url(config, "localhost")
    token = setup_token()
    {:ok, view, _} = live(conn, "/setup")
    refute has_element?(view, "[role='alert']")
    refute has_element?(view, "#setup-form button[disabled]")

    render_submit(view, "begin_setup", %{
      "setup" => %{"institution_name" => "Test College", "setup_token" => token}
    })

    refute has_element?(view, "#setup-form[phx-trigger-action]")
    assert has_element?(view, "[role='alert']", "Use a public HTTPS address")
    assert Repo.get!(BootstrapCredential, 1).step == :setup
  end

  defp set_endpoint_url(config, host) do
    Endpoint.config_change(
      [{Endpoint, Keyword.put(config, :url, scheme: "https", host: host, port: 443)}],
      []
    )
  end

  test "installed apps return to organization settings without connecting an unverified installation",
       %{
         conn: conn
       } do
    %{user: user} = GradePush.AccountsFixtures.bootstrap_fixture()

    assert {:error, {:redirect, %{to: "/teacher/settings?section=organizations&connect=true"}}} =
             live(conn, "/setup?installation_id=123&setup_action=install")

    assert GradePush.Classrooms.list_github_connections(user) == {:ok, []}
  end

  test "installation parameters cannot bypass initial setup", %{conn: conn} do
    setup_token()
    {:ok, view, _html} = live(conn, "/setup?installation_id=123&setup_action=install")

    assert has_element?(view, "#setup-form")
    refute Installation.configured?()

    render_patch(view, "/setup?setup_action=request")
    assert has_element?(view, "#setup-form")
    refute has_element?(view, "[data-ui='setup-status']")
  end

  test "an installation return preserves its state for the verified callback", %{conn: conn} do
    %{user: user} = GradePush.AccountsFixtures.bootstrap_fixture()

    assert {:error, {:redirect, %{to: path}}} =
             live(conn, "/setup?installation_id=123&setup_action=install&state=connection-state")

    assert URI.parse(path).path == "/github/organizations/callback"

    assert URI.decode_query(URI.parse(path).query) == %{
             "installation_id" => "123",
             "setup_action" => "install",
             "state" => "connection-state"
           }

    assert GradePush.Classrooms.list_github_connections(user) == {:ok, []}
  end

  test "configured installations welcome users with their institution and a continue action", %{
    conn: conn
  } do
    %{institution: institution} = GradePush.AccountsFixtures.bootstrap_fixture()
    {:ok, view, _} = live(conn, "/setup")

    assert has_element?(view, "h1", "Welcome to GradePush")
    assert has_element?(view, "h2", institution.name)
    assert has_element?(view, "[data-ui='setup-status'] .hero-check")
    assert has_element?(view, "a[href='/']", "Continue to GradePush")
    refute has_element?(view, "#setup-form")
    refute render(view) =~ "First-time setup"
  end

  test "installation requests explain approval instead of showing a successful connection", %{
    conn: conn
  } do
    %{user: user} = GradePush.AccountsFixtures.bootstrap_fixture()
    {:ok, view, _} = live(conn, "/setup?setup_action=request")

    assert has_element?(view, "[data-ui='setup-status']", "Organization approval required")
    assert has_element?(view, "[data-ui='setup-status'] .hero-clock")
    refute has_element?(view, "[data-ui='setup-status'] .hero-check")

    assert has_element?(
             view,
             "a[href='/teacher/settings?section=organizations&connect=true']",
             "Back to organizations"
           )

    assert has_element?(view, "a[data-ui=language][href='/setup?setup_action=request&locale=fr']")
    assert GradePush.Classrooms.list_github_connections(user) == {:ok, []}
  end

  test "valid setup submits only the manifest to GitHub without a second confirmation", %{
    conn: conn
  } do
    token = setup_token(:crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false))
    {:ok, view, _html} = live(conn, "/setup")

    assert has_element?(view, "#setup-form[phx-hook='SetupToken']")

    assert has_element?(
             view,
             "[data-ui~='setup-token-help'] code",
             "docker compose exec app gradepush-setup"
           )

    view
    |> form("#setup-form", setup: %{institution_name: "Test College", setup_token: token})
    |> render_submit()

    assert has_element?(view, "#setup-form[phx-trigger-action='true']")
    assert has_element?(view, "#setup-form [data-ui~='setup-progress']", "Opening GitHub...")
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
    token = setup_token(:crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false))
    conn = get(conn, "/setup")
    html = html_response(conn, 200)

    refute html =~ token
    assert html =~ "One-time setup token"
    assert html =~ "docker compose exec app gradepush-setup"
  end

  test "organization setup submits only the manifest to the selected organization", %{conn: conn} do
    token = setup_token()
    {:ok, view, _} = live(conn, "/setup")

    view
    |> form("#setup-form",
      setup: %{owner_type: "organization", institution_name: "Test College", setup_token: token}
    )
    |> render_change()

    assert has_element?(view, "input[name='setup[organization]'][required]")
    assert has_element?(view, "input[name='setup[institution_name]'][value='Test College']")
    assert has_element?(view, "input[name='setup[setup_token]'][value='#{token}']")

    view
    |> form("#setup-form",
      setup: %{
        institution_name: "Test College",
        setup_token: token,
        owner_type: "organization",
        organization: "my-college"
      }
    )
    |> render_submit()

    outgoing = follow_trigger_action(form(view, "#setup-form"), conn)
    assert outgoing.request_path == "/organizations/my-college/settings/apps/new"
    assert Map.keys(outgoing.body_params) == ["manifest"]
    refute outgoing.body_params["manifest"] =~ token
  end

  test "invalid organization preserves owner inputs, clears the token and allows switching back",
       %{
         conn: conn
       } do
    token = setup_token()
    {:ok, view, _} = live(conn, "/setup")

    render_submit(view, "begin_setup", %{
      "setup" => %{
        "institution_name" => "Test College",
        "setup_token" => token,
        "owner_type" => "organization",
        "organization" => "https://github.com/my-college"
      }
    })

    assert has_element?(view, "[role=alert]", "valid GitHub organization name")
    assert has_element?(view, "input[name='setup[institution_name]'][value='Test College']")

    assert has_element?(
             view,
             "input[name='setup[organization]'][value='https://github.com/my-college']"
           )

    assert has_element?(view, "input[name='setup[setup_token]'][value='']")
    assert Repo.get!(BootstrapCredential, 1).step == :setup

    view
    |> form("#setup-form", setup: %{owner_type: "personal"})
    |> render_change()

    refute has_element?(view, "input[name='setup[organization]']")
  end

  defp setup_token(configured_token \\ nil) do
    capture_log(fn ->
      assert {:ok, :created} = Installation.initialize_bootstrap(configured_token)
    end)

    credential = Repo.get!(BootstrapCredential, 1)
    assert {:ok, token} = Crypto.decrypt(credential.token_encrypted, "bootstrap.token")
    token
  end
end
