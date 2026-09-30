defmodule GradePush.Workers.ReconcileGrading do
  @moduledoc "Recovers grading deliveries whose push arrived after their retry budget."
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  alias GradePush.GitHub.Webhooks

  @impl Oban.Worker
  def perform(_job) do
    case Webhooks.reconcile_grading() do
      {:ok, _count} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
