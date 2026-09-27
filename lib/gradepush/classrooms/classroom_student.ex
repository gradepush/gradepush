defmodule GradePush.Classrooms.ClassroomStudent do
  use Ecto.Schema
  import Ecto.Changeset

  alias GradePush.Accounts.User
  alias GradePush.Classrooms.Classroom

  schema "classroom_students" do
    field :joined_at, :utc_datetime_usec
    field :removed_at, :utc_datetime_usec

    belongs_to :classroom, Classroom
    belongs_to :user, User

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:joined_at, :removed_at])
    |> validate_required([:joined_at])
    |> foreign_key_constraint(:classroom_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:classroom_id, :user_id])
  end
end
