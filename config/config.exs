import Config

config :gradepush,
  namespace: GradePush,
  start_endpoint: true,
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

config :gradepush, GradePushWeb.Gettext, default_locale: "en", locales: ~w(en fr)

config :gradepush, Oban,
  repo: GradePush.Repo,
  queues: [default: 10],
  plugins: [Oban.Plugins.Pruner]

import_config "#{config_env()}.exs"
