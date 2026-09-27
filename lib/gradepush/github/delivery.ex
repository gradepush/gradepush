defmodule GradePush.GitHub.Delivery do
  use Ecto.Schema
  import Ecto.Changeset

  schema "github_webhook_deliveries" do
    field :delivery_id, :string
    field :event, :string
    field :action, :string
    field :payload_sha256, :binary
    field :payload, :map
    field :status, :string, default: "pending"
    field :received_at, :utc_datetime_usec
    field :processed_at, :utc_datetime_usec
    field :last_error, :string
  end

  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [
      :delivery_id,
      :event,
      :action,
      :payload_sha256,
      :payload,
      :status,
      :received_at,
      :processed_at,
      :last_error
    ])
    |> validate_required([
      :delivery_id,
      :event,
      :payload_sha256,
      :payload,
      :status,
      :received_at
    ])
    |> validate_length(:delivery_id, min: 1, max: 100)
    |> validate_length(:event, min: 1, max: 100)
    |> validate_inclusion(:status, ~w(pending processed ignored failed))
    |> validate_length(:last_error, max: 100)
    |> unique_constraint(:delivery_id)
  end
end
