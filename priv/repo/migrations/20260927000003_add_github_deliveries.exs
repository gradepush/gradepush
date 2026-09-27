defmodule GradePush.Repo.Migrations.AddGitHubDeliveries do
  use Ecto.Migration

  def change do
    create table(:github_webhook_deliveries) do
      add :delivery_id, :string, null: false
      add :event, :string, null: false
      add :action, :string
      add :payload_sha256, :binary, null: false
      add :payload, :map, null: false
      add :status, :string, null: false, default: "pending"
      add :received_at, :utc_datetime_usec, null: false
      add :processed_at, :utc_datetime_usec
      add :last_error, :string
    end

    create unique_index(:github_webhook_deliveries, [:delivery_id])
    create index(:github_webhook_deliveries, [:received_at])
    create index(:github_webhook_deliveries, [:status, :received_at])

    create constraint(:github_webhook_deliveries, :github_webhook_delivery_status_check,
             check: "status IN ('pending', 'processed', 'ignored', 'failed')"
           )

    create constraint(:github_webhook_deliveries, :github_webhook_delivery_id_check,
             check: "length(delivery_id) BETWEEN 1 AND 100"
           )

    create constraint(:github_webhook_deliveries, :github_webhook_delivery_event_check,
             check: "length(event) BETWEEN 1 AND 100"
           )

    create constraint(:github_webhook_deliveries, :github_webhook_payload_size_check,
             check: "octet_length(payload_sha256) = 32"
           )
  end
end
