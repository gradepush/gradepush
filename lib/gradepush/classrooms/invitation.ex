defmodule GradePush.Classrooms.Invitation do
  use Ecto.Schema
  import Ecto.Changeset

  alias GradePush.Accounts.User
  alias GradePush.Classrooms.Classroom

  schema "classroom_invitations" do
    field :token_hash, :binary
    field :token_encrypted, :binary
    field :expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec

    belongs_to :classroom, Classroom
    belongs_to :created_by, User

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [
      :token_hash,
      :token_encrypted,
      :expires_at,
      :revoked_at,
      :classroom_id,
      :created_by_id
    ])
    |> validate_required([:token_hash, :token_encrypted, :classroom_id, :created_by_id])
    |> unique_constraint(:token_hash)
    |> foreign_key_constraint(:classroom_id)
    |> foreign_key_constraint(:created_by_id)
  end
end
