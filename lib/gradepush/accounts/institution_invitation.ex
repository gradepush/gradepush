defmodule GradePush.Accounts.InstitutionInvitation do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias GradePush.Accounts.{Institution, User}

  schema "institution_invitations" do
    field :token_hash, :binary
    field :role, Ecto.Enum, values: [:teacher], default: :teacher
    field :expires_at, :utc_datetime_usec
    field :accepted_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    belongs_to :institution, Institution
    belongs_to :invited_by, User
    belongs_to :accepted_by, User
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [
      :institution_id,
      :invited_by_id,
      :accepted_by_id,
      :token_hash,
      :role,
      :expires_at,
      :accepted_at,
      :revoked_at
    ])
    |> validate_required([:institution_id, :token_hash, :role, :expires_at])
    |> unique_constraint(:token_hash)
  end
end
