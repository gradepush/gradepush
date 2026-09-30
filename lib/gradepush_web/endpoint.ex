defmodule GradePushWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :gradepush

  @session_options [
    store: :cookie,
    key: "_gradepush_key",
    signing_salt: "q/VpENti",
    encryption_salt: "EN3v8K2p",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :gradepush,
    gzip: not code_reloading?,
    only: GradePushWeb.static_paths(),
    raise_on_missing_only: code_reloading?

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :gradepush
  end

  plug Plug.RequestId
  plug GradePushWeb.Plugs.TrustedProxy
  plug GradePushWeb.Metadata
  plug GradePushWeb.Plugs.SecureTransport
  plug GradePushWeb.Plugs.DemoBoundary

  plug Plug.Telemetry,
    event_prefix: [:phoenix, :endpoint],
    log: {__MODULE__, :request_log_level, []}

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    length: 2_000_000,
    body_reader: {GradePushWeb.Plugs.CacheBodyReader, :read_body, []},
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug GradePushWeb.Router

  def request_log_level(%{path_info: ["join" | _]}), do: false
  def request_log_level(%{path_info: ["cli", "authorize"]}), do: false
  def request_log_level(_conn), do: :info
end
