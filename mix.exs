defmodule GradePush.MixProject do
  use Mix.Project

  def project do
    [
      app: :gradepush,
      version: "0.1.9",
      elixir: "~> 1.20.4",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      releases: [gradepush: [steps: [:assemble, &copy_notices/1]]],
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def application do
    [
      mod: {GradePush.Application, []},
      extra_applications: [:logger, :runtime_tools, :inets, :ssl, :public_key]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp copy_notices(release) do
    for file <- ~w(LICENSE THIRD_PARTY_NOTICES.md) do
      File.cp!(file, Path.join(release.path, file))
    end

    for file <- Path.wildcard("deps/*/{LICENSE*,COPYING*,NOTICE*}"), File.regular?(file) do
      dependency = file |> Path.dirname() |> Path.basename()
      destination = Path.join([release.path, "third_party_licenses", dependency])
      File.mkdir_p!(destination)
      File.cp!(file, Path.join(destination, Path.basename(file)))
    end

    release
  end

  defp deps do
    [
      {:phoenix, "~> 1.8.15"},
      {:phoenix_ecto, "~> 4.7"},
      {:ecto_sql, "~> 3.14"},
      {:postgrex, "~> 0.22"},
      {:phoenix_html, "~> 4.3"},
      {:phoenix_live_reload, "~> 1.7", only: :dev},
      {:phoenix_live_view, "~> 1.2.12"},
      {:lazy_html, "~> 0.1.13", only: :test},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:mdex, "~> 0.14.0"},
      {:oban, "~> 2.24"},
      {:tz, "~> 0.28.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:bandit, "~> 1.12"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", &setup_dev_https/1, "ecto.setup", "assets.setup", "assets.build"],
      "phx.server": [&setup_dev_https/1, "phx.server"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind gradepush", "esbuild gradepush"],
      "assets.deploy": [
        "compile",
        "tailwind gradepush --minify",
        "esbuild gradepush --minify",
        "phx.digest"
      ],
      precommit: [
        "gettext.extract --check-up-to-date",
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "test"
      ]
    ]
  end

  defp setup_dev_https(_args) do
    supplied_certificate = System.get_env("TLS_CERTFILE") && System.get_env("TLS_KEYFILE")

    if Mix.env() == :dev && !supplied_certificate do
      Mix.Task.run("cmd", ["scripts/setup-https"])
    end
  end
end
