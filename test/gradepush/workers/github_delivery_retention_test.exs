defmodule GradePush.Workers.GitHubDeliveryRetentionTest do
  use GradePush.DataCase, async: true, group: :institution

  import Ecto.Query

  alias GradePush.GitHub.Delivery
  alias GradePush.Repo
  alias GradePush.Workers.PruneGitHubDeliveries

  test "prunes a bounded batch of old terminal deliveries and preserves recovery records" do
    old = DateTime.add(DateTime.utc_now(), -31 * 24 * 60 * 60, :second)
    recent = DateTime.add(DateTime.utc_now(), -24 * 60 * 60, :second)

    Repo.insert_all(
      Delivery,
      Enum.map(1..502, &delivery_attrs("processed-#{&1}", "processed", old))
    )

    Repo.insert_all(Delivery, [
      delivery_attrs("old-ignored", "ignored", old),
      delivery_attrs("old-pending", "pending", old),
      delivery_attrs("old-failed", "failed", old),
      delivery_attrs("recent-processed", "processed", recent)
    ])

    assert :ok = PruneGitHubDeliveries.perform(%Oban.Job{})

    assert Repo.aggregate(
             from(delivery in Delivery,
               where: delivery.received_at == ^old and delivery.status in ["processed", "ignored"]
             ),
             :count
           ) == 3

    assert Repo.get_by!(Delivery, delivery_id: "old-pending").status == "pending"
    assert Repo.get_by!(Delivery, delivery_id: "old-failed").status == "failed"
    assert Repo.get_by!(Delivery, delivery_id: "recent-processed").status == "processed"
  end

  defp delivery_attrs(delivery_id, status, received_at) do
    %{
      delivery_id: delivery_id,
      event: "push",
      payload_sha256: :crypto.hash(:sha256, delivery_id),
      payload: %{},
      status: status,
      received_at: received_at
    }
  end
end
