defmodule GradePush.Workers.PruneGitHubDeliveries do
  @moduledoc "Prunes old terminal webhook records in bounded batches."

  use Oban.Worker, queue: :maintenance, max_attempts: 5

  import Ecto.Query

  alias GradePush.GitHub.Delivery
  alias GradePush.Repo

  @batch_size 500
  @retention_seconds 30 * 24 * 60 * 60
  @terminal_statuses ~w(processed ignored)

  @impl Oban.Worker
  def perform(_job) do
    cutoff = DateTime.add(DateTime.utc_now(), -@retention_seconds, :second)

    old_delivery_ids =
      from(delivery in Delivery,
        where:
          delivery.status in ^@terminal_statuses and
            delivery.received_at < ^cutoff,
        order_by: [asc: delivery.received_at, asc: delivery.id],
        limit: ^@batch_size,
        select: delivery.id
      )

    from(delivery in Delivery, where: delivery.id in subquery(old_delivery_ids))
    |> Repo.delete_all()

    :ok
  end
end
