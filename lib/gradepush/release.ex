defmodule GradePush.Release do
  @moduledoc "Runs database migrations from the release before application startup."

  @app :gradepush
  @repos Application.compile_env(@app, :ecto_repos, [])

  def migrate do
    for repo <- @repos do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end
end
