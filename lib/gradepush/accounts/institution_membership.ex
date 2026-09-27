defmodule GradePush.Accounts.InstitutionMembership do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias GradePush.Accounts.{Institution, User}

  schema "institution_memberships" do
    field :role, Ecto.Enum, values: [:admin, :teacher, :student]
    field :student_name, :string
    field :student_id, :string
    field :joined_at, :utc_datetime_usec
    belongs_to :institution, Institution
    belongs_to :user, User

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:institution_id, :user_id, :role, :student_name, :student_id, :joined_at])
    |> validate_required([:institution_id, :user_id, :role, :joined_at])
    |> validate_length(:student_name, max: 255)
    |> validate_length(:student_id, max: 100)
    |> unique_constraint([:institution_id, :user_id, :role])
    |> foreign_key_constraint(:institution_id)
    |> foreign_key_constraint(:user_id)
  end
end
