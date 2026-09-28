defmodule GradePushWeb.CLIController do
  use GradePushWeb, :controller

  alias GradePush.CLI

  @max_request_bytes 8_192

  plug :put_cli_cache_headers

  def device(conn, _params) do
    with :ok <- request_size_ok(conn),
         %{} = body when map_size(body) == 0 <- conn.body_params,
         client_key <- remote_peer_key(conn.remote_ip),
         {:ok, result} <- CLI.request_device(client_key) do
      verification_uri = verification_uri()

      json(conn, %{
        device_code: result.device_code,
        user_code: result.user_code,
        verification_uri: verification_uri,
        verification_uri_complete:
          verification_uri <> "?" <> URI.encode_query(%{user_code: result.user_code}),
        expires_in: result.expires_in,
        interval: result.interval
      })
    else
      {:error, reason} -> cli_error(conn, reason)
      _other -> cli_error(conn, :invalid_request)
    end
  end

  def token(conn, _params) do
    with :ok <- request_size_ok(conn),
         %{"device_code" => device_code} = body when map_size(body) == 1 <- conn.body_params,
         true <- is_binary(device_code) and byte_size(device_code) in 1..128,
         {:ok, result} <- CLI.poll_device(device_code, remote_peer_key(conn.remote_ip)) do
      json(conn, result)
    else
      {:error, reason} -> cli_error(conn, reason)
      _other -> cli_error(conn, :invalid_request)
    end
  end

  def session(conn, _params) do
    if GradePush.Demo.enabled?() do
      cli_error(conn, :unavailable_in_demo)
    else
      with {:ok, token} <- bearer_token(conn),
           %GradePush.Accounts.User{} = user <- CLI.authenticate_access_token(token) do
        json(conn, %{user: %{login: user.login}})
      else
        _other -> unauthorized(conn)
      end
    end
  end

  def delete_session(conn, _params) do
    if GradePush.Demo.enabled?() do
      cli_error(conn, :unavailable_in_demo)
    else
      with {:ok, token} <- bearer_token(conn),
           %GradePush.Accounts.User{} <- CLI.authenticate_access_token(token),
           :ok <- CLI.revoke_access_token(token) do
        send_resp(conn, :no_content, "")
      else
        _other -> unauthorized(conn)
      end
    end
  end

  def repositories(conn, params) do
    if GradePush.Demo.enabled?() do
      cli_error(conn, :unavailable_in_demo)
    else
      with :ok <- request_size_ok(conn),
           {:ok, token} <- bearer_token(conn),
           %GradePush.Accounts.User{} = user <- CLI.authenticate_access_token(token),
           {:ok, query} <- repository_query(params),
           {:ok, manifest} <-
             CLI.list_repositories(user, query.classroom,
               assignment: query.assignment,
               page: query.page
             ) do
        json(conn, manifest)
      else
        {:error, reason} -> cli_error(conn, reason)
        _other -> unauthorized(conn)
      end
    end
  end

  defp repository_query(params) when is_map(params) do
    allowed = MapSet.new(["classroom", "assignment", "page"])

    if MapSet.subset?(MapSet.new(Map.keys(params)), allowed) do
      classroom = params["classroom"]
      assignment = params["assignment"]

      with true <- is_binary(classroom) and byte_size(classroom) in 1..100,
           true <-
             is_nil(assignment) or (is_binary(assignment) and byte_size(assignment) in 1..100),
           {:ok, page} <- parse_page(params["page"]) do
        {:ok, %{classroom: classroom, assignment: assignment, page: page}}
      else
        _other -> {:error, :invalid_request}
      end
    else
      {:error, :invalid_request}
    end
  end

  defp repository_query(_params), do: {:error, :invalid_request}

  defp parse_page(nil), do: {:ok, 1}

  defp parse_page(value) when is_binary(value) and byte_size(value) <= 9 do
    case Integer.parse(value) do
      {page, ""} when page in 1..1_000_000 -> {:ok, page}
      _other -> {:error, :invalid_request}
    end
  end

  defp parse_page(_value), do: {:error, :invalid_request}

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when byte_size(token) in 1..128 -> {:ok, token}
      _other -> {:error, :unauthorized}
    end
  end

  defp request_size_ok(conn) do
    case get_req_header(conn, "content-length") do
      [value] ->
        case Integer.parse(value) do
          {bytes, ""} when bytes in 0..@max_request_bytes -> :ok
          _other -> {:error, :request_too_large}
        end

      [] ->
        :ok

      _other ->
        {:error, :invalid_request}
    end
  end

  defp verification_uri do
    GradePushWeb.Endpoint.url()
    |> URI.merge("/cli/authorize")
    |> URI.to_string()
  end

  defp remote_peer_key(remote_ip) do
    remote_ip
    |> :inet.ntoa()
    |> List.to_string()
  end

  defp cli_error(conn, :rate_limited) do
    conn
    |> put_resp_header("retry-after", "60")
    |> put_status(:too_many_requests)
    |> json(%{error: "rate_limited"})
  end

  defp cli_error(conn, :unavailable_in_demo) do
    conn |> put_status(:forbidden) |> json(%{error: "unavailable_in_demo"})
  end

  defp cli_error(conn, reason)
       when reason in [
              :authorization_pending,
              :slow_down,
              :expired_token,
              :access_denied,
              :invalid_grant
            ] do
    conn |> put_status(:bad_request) |> json(%{error: Atom.to_string(reason)})
  end

  defp cli_error(conn, :unauthorized), do: unauthorized(conn)

  defp cli_error(conn, :not_found) do
    conn |> put_status(:not_found) |> json(%{error: "not_found"})
  end

  defp cli_error(conn, :invalid_request) do
    conn |> put_status(:bad_request) |> json(%{error: "invalid_request"})
  end

  defp cli_error(conn, :request_too_large) do
    conn |> put_status(:request_entity_too_large) |> json(%{error: "request_too_large"})
  end

  defp cli_error(conn, _reason) do
    conn |> put_status(:bad_request) |> json(%{error: "invalid_request"})
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_header("www-authenticate", "Bearer")
    |> put_status(:unauthorized)
    |> json(%{error: "unauthorized"})
  end

  defp put_cli_cache_headers(conn, _options) do
    Plug.Conn.put_resp_header(conn, "cache-control", "no-store")
  end
end
