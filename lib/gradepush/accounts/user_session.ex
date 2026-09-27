defmodule GradePush.Accounts.UserSession do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias GradePush.Accounts.User

  schema "user_sessions" do
    field :token_hash, :binary
    field :expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    belongs_to :user, User
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:user_id, :token_hash, :expires_at, :revoked_at])
    |> validate_required([:user_id, :token_hash, :expires_at])
    |> unique_constraint(:token_hash)
  end
end
