import Config

config :gradepush, GradePushWeb.Endpoint, cache_static_manifest: "priv/static/cache_manifest.json"

config :gradepush, GradePushWeb.Endpoint,
  force_ssl: [
    rewrite_on: [:x_forwarded_proto],
    exclude: [
      hosts: ["localhost", "127.0.0.1"]
    ]
  ]

config :logger, level: :info
