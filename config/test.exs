import Config

config :gradepush, GradePush.Repo,
  username: System.get_env("DB_USER", "gradepush"),
  password: System.get_env("DB_PASSWORD", "gradepush"),
  hostname: System.get_env("DB_HOST", "localhost"),
  port: String.to_integer(System.get_env("DB_PORT", "54329")),
  database: "gradepush_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :gradepush, GradePushWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "6d16MWdzt2QF1PzPJwDVRbRfTXPV5UNkbkbIL/X/NYnDnW9Wi+6n3t7hYO65Lwm1",
  server: false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :phoenix,
  sort_verified_routes_query_params: true

config :gradepush, Oban, testing: :manual
