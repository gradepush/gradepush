defmodule GradePush.Operations do
  @moduledoc "Operator-scoped local diagnostics without secrets or host access."
  import Ecto.Query

  alias GradePush.{Accounts, Installation, Repo}

  def snapshot(actor) do
    if Accounts.operator?(actor) do
      jobs =
        Repo.all(from j in Oban.Job, group_by: j.state, select: {j.state, count(j.id)})
        |> Map.new()

      {:ok,
       %{
         database: :connected,
         github_app: Installation.github_app_metadata(),
         last_webhook_at:
           Repo.one(from d in GradePush.GitHub.Delivery, select: max(d.received_at)),
         jobs: jobs,
         checked_at: DateTime.utc_now()
       }}
    else
      {:error, :unauthorized}
    end
  end
end
