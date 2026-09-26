import Config

config :gradepush, GradePush.Repo,
  username: System.get_env("DB_USER", "gradepush"),
  password: System.get_env("DB_PASSWORD", "gradepush"),
  hostname: System.get_env("DB_HOST", "localhost"),
  port: String.to_integer(System.get_env("DB_PORT", "54329")),
  database: System.get_env("DB_NAME", "gradepush_dev"),
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :gradepush, GradePushWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "7bDGN0WZOM4ErnMe0YtgaLE1Pdb7KtdzzI2+l7CRxEWq0VLqwJ+p651glyXxAR7M",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:gradepush, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:gradepush, ~w(--watch)]}
  ]

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true
