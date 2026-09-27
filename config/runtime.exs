import Config

config :gradepush, :start_endpoint, System.get_env("START_ENDPOINT", "true") == "true"

demo_mode = System.get_env("DEMO_MODE", "false") == "true"
config :gradepush, :demo_mode, demo_mode

if demo_mode do
  config :gradepush, GradePush.GitHub, adapter: GradePush.GitHub.Fake

  config :gradepush, Oban,
    plugins: [
      {Oban.Plugins.Pruner, max_age: 7 * 24 * 60 * 60},
      {Oban.Plugins.Cron,
       crontab: [
         {"0 * * * *", GradePush.Workers.PruneGitHubDeliveries},
         {"0 4 * * *", GradePush.Workers.ResetDemo}
       ]}
    ]
end

config :gradepush,
       :ui_preview,
       System.get_env("UI_PREVIEW", "false") == "true" or config_env() == :test

credential_key =
  case System.get_env("CREDENTIAL_ENCRYPTION_KEY") do
    nil ->
      if config_env() == :prod do
        raise "CREDENTIAL_ENCRYPTION_KEY must be configured"
      else
        :crypto.hash(:sha256, "gradepush-local-development-credentials")
      end

    encoded ->
      case Base.decode64(encoded) do
        {:ok, key} when byte_size(key) == 32 -> key
        _ -> raise "CREDENTIAL_ENCRYPTION_KEY must be a base64-encoded 32-byte key"
      end
  end

config :gradepush, GradePush.Crypto, credential_encryption_key: credential_key

if server = System.get_env("PHX_SERVER") do
  config :gradepush, GradePushWeb.Endpoint, server: server == "true"
end

config :gradepush, GradePushWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  config :gradepush, GradePushWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        ~r"priv/gettext/.*\.po$"E,
        ~r"lib/gradepush_web/router\.ex$"E,
        ~r"lib/gradepush_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :test and System.get_env("TEST_DATABASE_URL") do
  config :gradepush, GradePush.Repo, url: System.fetch_env!("TEST_DATABASE_URL")
end

if config_env() == :prod do
  database_config =
    if database_url = System.get_env("DATABASE_URL") do
      [url: database_url]
    else
      [
        hostname: System.fetch_env!("DB_HOST"),
        port: String.to_integer(System.get_env("DB_PORT", "5432")),
        username: System.fetch_env!("DB_USER"),
        password: System.fetch_env!("DB_PASSWORD"),
        database: System.get_env("DB_NAME", "gradepush")
      ]
    end

  config :gradepush,
         GradePush.Repo,
         database_config ++ [pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))]

  if System.get_env("START_ENDPOINT", "true") == "true" do
    secret_key_base = System.fetch_env!("SECRET_KEY_BASE")
    host = System.get_env("PHX_HOST", "localhost")
    scheme = System.get_env("PHX_SCHEME", "https")

    unless scheme in ["http", "https"] do
      raise "PHX_SCHEME must be http or https"
    end

    if scheme == "http" and host not in ["localhost", "127.0.0.1"] do
      raise "HTTP is supported only for local development; configure HTTPS for a public host"
    end

    config :gradepush, GradePushWeb.Endpoint,
      url: [
        host: host,
        scheme: scheme,
        port: String.to_integer(System.get_env("PHX_URL_PORT", "443"))
      ],
      http: [ip: {0, 0, 0, 0}],
      secret_key_base: secret_key_base
  end
end
