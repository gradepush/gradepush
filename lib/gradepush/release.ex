defmodule GradePush.Release do
  @moduledoc "Provides operator commands for the application release."

  @app :gradepush
  @repos Application.compile_env(@app, :ecto_repos, [])

  def setup_link do
    case GradePush.Installation.setup_link(GradePushWeb.Endpoint.url()) do
      {:ok, url} -> IO.puts(url)
      {:error, :setup_not_available} -> raise "Initial setup is not available on this instance."
    end
  end

  def migrate do
    for repo <- @repos do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end
end
