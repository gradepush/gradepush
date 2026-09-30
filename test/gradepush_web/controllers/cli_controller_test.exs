defmodule GradePushWeb.CLIControllerTest do
  use GradePushWeb.ConnCase, async: false

  import Ecto.Query
  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures

  alias GradePush.Assignments.{Assignment, Repository, Subject}
  alias GradePush.CLI
  alias GradePush.CLI.DeviceAuthorization
  alias GradePush.Crypto
  alias GradePush.Repo

  setup do
    previous_demo = Application.get_env(:gradepush, :demo_mode, false)
    Application.put_env(:gradepush, :demo_mode, false)

    on_exit(fn -> Application.put_env(:gradepush, :demo_mode, previous_demo) end)
    :ok
  end

  test "device flow authenticates session, returns scoped repositories, and revokes its token", %{
    conn: conn
  } do
    teacher = teacher_fixture()
    classroom = classroom_fixture(teacher, %{title: "CLI API", code: "CLI-API"})
    assignment = assignment_fixture(teacher, classroom, %{title: "CLI Repository"})
    seed_ready_repository(assignment)

    device_conn = post_json(conn, "/api/v1/cli/device", %{})
    assert device_conn.status == 200
    assert get_resp_header(device_conn, "cache-control") == ["no-store"]
    device = json_response(device_conn, 200)
    assert device["expires_in"] == 600
    assert device["interval"] == 5
    assert device["verification_uri"] =~ "/cli/authorize"

    complete_uri = URI.parse(device["verification_uri_complete"])
    complete_query = URI.decode_query(complete_uri.query)
    assert complete_query["user_code"] == device["user_code"]

    authorization =
      Repo.get_by!(DeviceAuthorization, device_code_hash: Crypto.hash(device["device_code"]))

    Repo.update_all(
      from(record in DeviceAuthorization, where: record.id == ^authorization.id),
      set: [inserted_at: ago(10)]
    )

    pending_conn = post_json(conn, "/api/v1/cli/token", %{device_code: device["device_code"]})
    assert json_response(pending_conn, 400) == %{"error" => "authorization_pending"}
    assert get_resp_header(pending_conn, "cache-control") == ["no-store"]

    assert :ok = CLI.approve(teacher, device["user_code"])

    Repo.update_all(
      from(record in DeviceAuthorization, where: record.id == ^authorization.id),
      set: [last_polled_at: ago(10)]
    )

    token_conn = post_json(conn, "/api/v1/cli/token", %{device_code: device["device_code"]})
    token = json_response(token_conn, 200)
    assert token["token_type"] == "Bearer"
    assert token["expires_in"] == 7_776_000

    session_conn = bearer_conn(conn, token["access_token"]) |> get("/api/v1/cli/session")
    assert json_response(session_conn, 200) == %{"user" => %{"login" => teacher.login}}

    path = "/api/v1/cli/repositories?" <> URI.encode_query(%{classroom: classroom.slug})
    manifest_conn = bearer_conn(conn, token["access_token"]) |> get(path)

    assert json_response(manifest_conn, 200) == %{
             "schema_version" => 1,
             "classroom" => %{"slug" => classroom.slug},
             "repositories" => [
               %{"assignment" => assignment.slug, "full_name" => "gradepush-test/cli-api"}
             ],
             "next_page" => nil
           }

    delete_conn = bearer_conn(conn, token["access_token"]) |> delete("/api/v1/cli/session")
    assert response(delete_conn, 204) == ""

    rejected = bearer_conn(conn, token["access_token"]) |> get("/api/v1/cli/session")
    assert json_response(rejected, 401) == %{"error" => "unauthorized"}
  end

  test "clients behind a trusted proxy have separate quotas and spoofed prefixes cannot reset one" do
    previous = Application.get_env(:gradepush, :trusted_proxies, [])
    Application.put_env(:gradepush, :trusted_proxies, ["192.0.2.42"])
    on_exit(fn -> Application.put_env(:gradepush, :trusted_proxies, previous) end)

    request = fn header ->
      %{build_conn() | remote_ip: {192, 0, 2, 42}}
      |> put_req_header("x-forwarded-for", header)
      |> post_json("/api/v1/cli/device", %{})
    end

    assert Enum.all?(1..60, fn _ -> request.("198.51.100.31").status == 200 end)
    assert request.("198.51.100.31").status == 429
    assert request.("203.0.113.88, 198.51.100.31").status == 429
    assert request.("198.51.100.32").status == 200
  end

  test "rejects malformed request bodies and disables every CLI API endpoint in demo mode", %{
    conn: conn
  } do
    malformed = post_json(conn, "/api/v1/cli/token", %{device_code: ["array"]})
    assert json_response(malformed, 400) == %{"error" => "invalid_request"}
    assert get_resp_header(malformed, "cache-control") == ["no-store"]

    Application.put_env(:gradepush, :demo_mode, true)
    on_exit(fn -> Application.put_env(:gradepush, :demo_mode, false) end)

    device = post_json(conn, "/api/v1/cli/device", %{})
    assert json_response(device, 403) == %{"error" => "unavailable_in_demo"}

    session = get(conn, "/api/v1/cli/session")
    assert json_response(session, 403) == %{"error" => "unavailable_in_demo"}

    repositories = get(conn, "/api/v1/cli/repositories?classroom=anything")
    assert json_response(repositories, 403) == %{"error" => "unavailable_in_demo"}
  end

  defp teacher_fixture do
    teacher = user_fixture(%{login: "api-teacher-#{System.unique_integer([:positive])}"})
    teacher_membership_fixture(teacher)
    teacher
  end

  defp seed_ready_repository(%Assignment{} = assignment) do
    student = user_fixture(%{login: "api-student-#{System.unique_integer([:positive])}"})
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    subject =
      %Subject{}
      |> Subject.changeset(%{
        assignment_id: assignment.id,
        kind: "individual",
        user_id: student.id,
        accepted_at: now
      })
      |> Repo.insert!()

    %Repository{}
    |> Repository.changeset(%{
      subject_id: subject.id,
      state: "ready",
      full_name: "gradepush-test/cli-api"
    })
    |> Repo.insert!()
  end

  defp post_json(conn, path, body) do
    conn
    |> Plug.Conn.put_req_header("accept", "application/json")
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(body))
  end

  defp bearer_conn(conn, token) do
    Plug.Conn.put_req_header(conn, "authorization", "Bearer " <> token)
  end

  defp ago(seconds), do: DateTime.add(DateTime.utc_now(), -seconds, :second)
end
