defmodule GradePush.GitHub.HTTP do
  @moduledoc false

  def request(method, url, headers, body) do
    with :ok <- ensure_http_clients_started(),
         {:ok, parsed} <- parse_url(url),
         :ok <- validate_destination(parsed),
         request <- http_request(method, url, headers, body),
         {:ok, {{_version, status, _reason}, response_headers, response_body}} <-
           :httpc.request(method, request, http_options(parsed), body_format: :binary) do
      {:ok,
       %{
         status: status,
         headers:
           Enum.map(response_headers, fn {key, value} -> {to_string(key), to_string(value)} end),
         body: response_body
       }}
    else
      {:error, {:failed_connect, _details}} -> {:error, :connection_failed}
      {:error, :timeout} -> {:error, :timeout}
      {:error, reason} -> {:error, reason}
    end
  end

  defp http_request(method, url, headers, nil) when method in [:get, :delete, :head] do
    {String.to_charlist(url), encode_headers(headers)}
  end

  defp http_request(_method, url, headers, body) do
    {String.to_charlist(url), encode_headers(headers), ~c"application/json", body || ""}
  end

  defp http_options(%URI{scheme: "https", host: host}) do
    [
      autoredirect: false,
      connect_timeout: 5_000,
      timeout: 15_000,
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        server_name_indication: String.to_charlist(host),
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ],
        depth: 5
      ]
    ]
  end

  defp http_options(_), do: [autoredirect: false, connect_timeout: 5_000, timeout: 15_000]

  defp parse_url(url) do
    uri = URI.parse(url)

    if uri.scheme && uri.host && uri.userinfo == nil && uri.fragment == nil do
      {:ok, uri}
    else
      {:error, :invalid_url}
    end
  end

  defp validate_destination(%URI{scheme: "https", host: host})
       when host in ["api.github.com", "github.com"],
       do: :ok

  defp validate_destination(_), do: {:error, :insecure_destination}

  defp encode_headers(headers),
    do: Enum.map(headers, fn {key, value} -> {to_charlist(key), to_charlist(value)} end)

  defp ensure_http_clients_started do
    case Application.ensure_all_started(:inets) do
      {:ok, _apps} ->
        case Application.ensure_all_started(:ssl) do
          {:ok, _apps} -> :ok
          {:error, _} -> {:error, :ssl_unavailable}
        end

      {:error, _} ->
        {:error, :http_client_unavailable}
    end
  end
end
