defmodule GradePushWeb.CLIAuthorizationLiveTest do
  use GradePushWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import GradePush.AccountsFixtures

  alias GradePush.CLI

  test "authorization requires explicit confirmation and issues only a CLI token", %{conn: conn} do
    %{user: teacher} = bootstrap_fixture()
    {:ok, device} = CLI.request_device("browser-#{System.unique_integer([:positive])}")
    conn = log_in_user(conn, teacher)

    {:ok, view, _} = live(conn, "/cli/authorize?user_code=#{device.user_code}&locale=fr")
    assert has_element?(view, "input[name='cli[user_code]']")
    assert has_element?(view, "button", "Autoriser le terminal")
    assert has_element?(view, "a[data-ui=language][href*='user_code=']")

    view
    |> form("#cli-authorization", cli: %{user_code: device.user_code})
    |> render_submit(%{"decision" => "approve"})

    assert has_element?(view, "[role=status]", "Terminal autorisé")
    refute has_element?(view, "#cli-authorization")

    GradePush.Repo.get_by!(GradePush.CLI.DeviceAuthorization,
      device_code_hash: GradePush.Crypto.hash(device.device_code)
    )
    |> Ecto.Changeset.change(inserted_at: DateTime.add(DateTime.utc_now(), -6, :second))
    |> GradePush.Repo.update!()

    response =
      build_conn()
      |> post("/api/v1/cli/token", %{device_code: device.device_code})
      |> json_response(200)

    assert is_binary(response["access_token"])
    refute GradePush.Accounts.get_user_by_session_token(response["access_token"])
  end

  test "declining a terminal does not grant a session", %{conn: conn} do
    %{user: teacher} = bootstrap_fixture()
    {:ok, device} = CLI.request_device("browser-#{System.unique_integer([:positive])}")

    {:ok, view, _} =
      conn |> log_in_user(teacher) |> live("/cli/authorize?user_code=#{device.user_code}")

    view
    |> form("#cli-authorization", cli: %{user_code: device.user_code})
    |> render_submit(%{"decision" => "deny"})

    assert has_element?(view, "[role=status]", "Request declined")

    response =
      build_conn()
      |> post("/api/v1/cli/token", %{device_code: device.device_code})
      |> json_response(400)

    assert response["error"] == "access_denied"
  end

  test "anonymous users return to the terminal code after signing in", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{"ui_preview" => false})
      |> get("/cli/authorize?user_code=ABCD-EFGH")

    assert get_session(conn, :return_to) == "/cli/authorize?user_code=ABCD-EFGH"
    assert redirected_to(conn) == "/auth/sign-in"
  end

  test "students cannot open terminal authorization", %{conn: conn} do
    %{user: _teacher} = bootstrap_fixture()
    student = user_fixture()

    assert {:error, {:redirect, %{to: "/"}}} =
             conn |> log_in_user(student) |> live("/cli/authorize")
  end

  test "malformed codes stay in the form with an actionable error", %{conn: conn} do
    %{user: teacher} = bootstrap_fixture()
    {:ok, view, _} = conn |> log_in_user(teacher) |> live("/cli/authorize")

    view
    |> form("#cli-authorization", cli: %{user_code: "not-a-code"})
    |> render_submit(%{"decision" => "approve"})

    assert has_element?(view, "[role=alert]", "invalid or expired")
  end
end
