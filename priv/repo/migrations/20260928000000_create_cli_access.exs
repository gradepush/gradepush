defmodule GradePush.Repo.Migrations.CreateCliAccess do
  use Ecto.Migration

  def change do
    create table(:cli_device_authorizations) do
      add :device_code_hash, :binary, null: false
      add :user_code_hash, :binary, null: false
      add :status, :string, null: false, default: "pending"
      add :expires_at, :utc_datetime_usec, null: false
      add :poll_interval_seconds, :integer, null: false, default: 5
      add :last_polled_at, :utc_datetime_usec
      add :approved_at, :utc_datetime_usec
      add :denied_at, :utc_datetime_usec
      add :consumed_at, :utc_datetime_usec
      add :user_id, references(:users, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:cli_device_authorizations, [:device_code_hash])
    create unique_index(:cli_device_authorizations, [:user_code_hash])
    create index(:cli_device_authorizations, [:status, :expires_at])
    create index(:cli_device_authorizations, [:expires_at])
    create index(:cli_device_authorizations, [:user_id, :status])

    create constraint(:cli_device_authorizations, :cli_device_authorizations_status_check,
             check: "status IN ('pending', 'approved', 'denied', 'consumed')"
           )

    create constraint(
             :cli_device_authorizations,
             :cli_device_authorizations_poll_interval_check,
             check: "poll_interval_seconds BETWEEN 5 AND 3600"
           )

    create table(:cli_access_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :revoked_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:cli_access_tokens, [:token_hash])
    create index(:cli_access_tokens, [:user_id, :expires_at])
    create index(:cli_access_tokens, [:expires_at])
    create index(:cli_access_tokens, [:revoked_at])
  end
end
