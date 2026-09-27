defmodule GradePushWeb.GitHubWebhookController do
  use GradePushWeb, :controller

  alias GradePush.GitHub.Webhooks

  def create(conn, _params) do
    case Webhooks.receive(conn.assigns[:raw_body], conn.req_headers) do
      {:ok, outcome} when outcome in [:accepted, :duplicate, :ignored] ->
        send_resp(conn, :accepted, "")

      {:error, :invalid_signature} ->
        send_resp(conn, :unauthorized, "")

      {:error, :unsupported_event} ->
        send_resp(conn, :accepted, "")

      {:error, :not_configured} ->
        send_resp(conn, :service_unavailable, "")

      {:error, reason} when reason in [:invalid_webhook, :delivery_payload_conflict] ->
        send_resp(conn, :bad_request, "")

      {:error, _reason} ->
        send_resp(conn, :service_unavailable, "")
    end
  end
end
