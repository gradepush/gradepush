defmodule GradePushWeb.Plugs.BrowserSecurity do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  def init(options), do: options

  def call(conn, _options) do
    origin = URI.parse(GradePushWeb.Endpoint.url())
    websocket = %{origin | scheme: if(origin.scheme == "https", do: "wss", else: "ws")}

    policy =
      Enum.join(
        [
          "default-src 'none'",
          "base-uri 'none'",
          "object-src 'none'",
          "frame-ancestors 'self'",
          "frame-src 'self'",
          "script-src 'self'",
          # LiveView transitions and the progress bar set element styles at runtime.
          "style-src 'self' 'unsafe-inline'",
          "img-src 'self' data: https:",
          "font-src 'self'",
          "connect-src 'self' #{URI.to_string(websocket)}",
          "form-action 'self' https://github.com"
        ],
        "; "
      )

    conn
    |> put_resp_header("content-security-policy", policy)
    |> put_resp_header("referrer-policy", "strict-origin-when-cross-origin")
    |> put_resp_header("permissions-policy", "camera=(), microphone=(), geolocation=()")
  end
end
