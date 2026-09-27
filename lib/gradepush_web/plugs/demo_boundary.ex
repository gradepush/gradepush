defmodule GradePushWeb.Plugs.DemoBoundary do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  def init(options), do: options

  def call(conn, _options) do
    if Application.get_env(:gradepush, :demo_mode, false) and blocked?(conn.path_info) do
      block(conn)
    else
      conn
    end
  end

  defp blocked?(["auth", "logout"]), do: false
  defp blocked?([section | _]) when section in ["auth", "setup", "join", "webhooks"], do: true
  defp blocked?(_), do: false

  defp block(%{method: "GET"} = conn) do
    conn |> Phoenix.Controller.redirect(to: "/demo") |> halt()
  end

  defp block(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(:forbidden, Jason.encode!(%{error: "unavailable_in_demo"}))
    |> halt()
  end
end
