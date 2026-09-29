defmodule GradePushWeb.OrganizationControllerTest do
  use GradePushWeb.ConnCase, async: true

  import GradePush.AccountsFixtures
  import Phoenix.LiveViewTest
  alias GradePush.{Accounts, Classrooms}
  alias GradePush.GitHub.Fake

  @settings "/teacher/settings?section=organizations"

  test "GitHub return connects once without a second form and consumes the browser state", %{
    conn: conn
  } do
    %{user: teacher} = configured_gradepush_fixture()
    started = conn |> log_in_user(teacher) |> get("/github/organizations/connect")
    url = redirected_to(started)
    assert url =~ "https://github.com/apps/gradepush-test/installations/new?state="
    state = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("state")
    callback = callback_path(state)
    completed = started |> recycle() |> get(callback)
    assert redirected_to(completed) == @settings
    assert is_nil(get_session(completed, :organization_connection))
    assert {:ok, [connection]} = Classrooms.list_github_connections(teacher)
    assert connection.login == "gradepush-test"
    assert Phoenix.Flash.get(completed.assigns.flash, :info) =~ "connected to your account"
    replayed = completed |> recycle() |> get(callback)
    assert Phoenix.Flash.get(replayed.assigns.flash, :error) =~ "expired"
  end

  test "forged, expired and account-mismatched callbacks cannot create a connection", %{
    conn: conn
  } do
    %{user: teacher} = configured_gradepush_fixture()
    conn = log_in_user(conn, teacher)

    for pending <- [
          nil,
          %{
            "state" => "expected",
            "user_id" => teacher.id,
            "issued_at" => System.system_time(:second) - 901
          },
          %{
            "state" => "expected",
            "user_id" => teacher.id + 1,
            "issued_at" => System.system_time(:second)
          },
          %{
            "state" => "different",
            "user_id" => teacher.id,
            "issued_at" => System.system_time(:second)
          }
        ] do
      response =
        conn
        |> init_test_session(%{organization_connection: pending})
        |> get(callback_path("expected"))

      assert redirected_to(response) == @settings
      assert {:ok, []} = Classrooms.list_github_connections(teacher)
    end
  end

  test "valid state cannot connect a personal account or an unapproved organization", %{
    conn: conn
  } do
    %{user: teacher} = configured_gradepush_fixture()
    started = conn |> log_in_user(teacher) |> get("/github/organizations/connect")
    state = get_session(started, :organization_connection)["state"]
    {:ok, [installation]} = Fake.list_installations(%{})
    Fake.set_installations([put_in(installation, ["account", "type"], "User")])
    response = started |> recycle() |> get(callback_path(state))
    assert Phoenix.Flash.get(response.assigns.flash, :error) =~ "personal account"
    assert {:ok, []} = Classrooms.list_github_connections(teacher)

    started = response |> recycle() |> get("/github/organizations/connect")
    state = get_session(started, :organization_connection)["state"]

    response =
      started
      |> recycle()
      |> get(
        "/github/organizations/callback?" <>
          URI.encode_query(%{setup_action: "request", state: state})
      )

    assert Phoenix.Flash.get(response.assigns.flash, :info) =~ "must approve"
    assert {:ok, []} = Classrooms.list_github_connections(teacher)
  end

  test "ordinary signed-in users cannot start an installation connection", %{conn: conn} do
    configured_gradepush_fixture()
    student = user_fixture()
    refute Accounts.teacher?(student)
    response = conn |> log_in_user(student) |> get("/github/organizations/connect")
    assert redirected_to(response) == @settings
    assert is_nil(get_session(response, :organization_connection))
  end

  test "an inaccessible installation returns recovery links and a retry action", %{conn: conn} do
    %{user: teacher} = configured_gradepush_fixture()
    started = conn |> log_in_user(teacher) |> get("/github/organizations/connect")
    state = get_session(started, :organization_connection)["state"]
    Fake.set_installations([])
    response = started |> recycle() |> get(callback_path(state))

    assert redirected_to(response) == @settings
    assert {:ok, []} = Classrooms.list_github_connections(teacher)
    {:ok, view, _} = response |> recycle() |> live(@settings)

    assert has_element?(view, "[data-ui=organization-connection-help]", "separate steps")

    assert has_element?(
             view,
             "a[href='https://github.com/apps/gradepush-test/installations/new']"
           )

    assert has_element?(view, "a[href='https://github.com/settings/apps/authorizations']")
    view |> element("button", "Retry loading organizations") |> render_click()
    assert has_element?(view, "[data-ui=organization-connection]")
  end

  defp callback_path(state),
    do:
      "/github/organizations/callback?" <>
        URI.encode_query(%{installation_id: "123", setup_action: "install", state: state})
end
