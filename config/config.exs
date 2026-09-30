import Config

config :gradepush,
  namespace: GradePush,
  start_endpoint: true,
  ui_preview: false,
  ecto_repos: [GradePush.Repo],
  generators: [timestamp_type: :utc_datetime]

config :gradepush, GradePushWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: GradePushWeb.ErrorHTML, json: GradePushWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: GradePush.PubSub,
  live_view: [signing_salt: "NOfFeC50"]

config :phoenix_live_view,
  root_tag_attribute: "phx-r"

config :esbuild,
  version: "0.28.2",
  gradepush: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :tailwind,
  version: "4.3.3",
  gradepush: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

config :elixir, :time_zone_database, Tz.TimeZoneDatabase
config :gradepush, :timezone, "America/Toronto"

config :phoenix, :filter_parameters, [
  "password",
  "secret",
  "token",
  "code",
  "state",
  "pem",
  "private_key",
  "manifest",
  "return_to",
  "nonce",
  "profile"
]

config :gradepush, GradePush.GitHub,
  adapter: GradePush.GitHub.Real,
  api_url: "https://api.github.com",
  web_url: "https://github.com",
  api_version: "2026-03-10"

config :gradepush, GradePushWeb.Gettext, default_locale: "en", locales: ~w(en fr)

config :gradepush, Oban,
  repo: GradePush.Repo,
  queues: [default: 10, github: 5, maintenance: 1],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 7 * 24 * 60 * 60},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 * * * *", GradePush.Workers.PruneGitHubDeliveries},
       {"*/5 * * * *", GradePush.Workers.ReconcileGrading}
     ]}
  ]

import_config "#{config_env()}.exs"
