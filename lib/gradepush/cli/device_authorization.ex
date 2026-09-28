defmodule GradePush.CLI.DeviceAuthorization do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias GradePush.Accounts.User

  schema "cli_device_authorizations" do
    field :device_code_hash, :binary
    field :user_code_hash, :binary
    field :status, :string, default: "pending"
    field :expires_at, :utc_datetime_usec
    field :poll_interval_seconds, :integer, default: 5
    field :last_polled_at, :utc_datetime_usec
    field :approved_at, :utc_datetime_usec
    field :denied_at, :utc_datetime_usec
    field :consumed_at, :utc_datetime_usec

    belongs_to :user, User

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(authorization, attrs) do
    authorization
    |> cast(attrs, [
      :device_code_hash,
      :user_code_hash,
      :status,
      :expires_at,
      :poll_interval_seconds,
      :last_polled_at,
      :approved_at,
      :denied_at,
      :consumed_at,
      :user_id
    ])
    |> validate_required([
      :device_code_hash,
      :user_code_hash,
      :status,
      :expires_at,
      :poll_interval_seconds
    ])
    |> validate_inclusion(:status, ~w(pending approved denied consumed))
    |> validate_number(:poll_interval_seconds,
      greater_than_or_equal_to: 5,
      less_than_or_equal_to: 3600
    )
    |> unique_constraint(:device_code_hash)
    |> unique_constraint(:user_code_hash)
    |> foreign_key_constraint(:user_id)
  end
end
