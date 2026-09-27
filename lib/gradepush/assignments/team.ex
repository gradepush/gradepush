defmodule GradePush.Assignments.Team do
  use Ecto.Schema
  import Ecto.Changeset

  alias GradePush.Accounts.User
  alias GradePush.Assignments.{Assignment, TeamMember}

  schema "assignment_teams" do
    field :name, :string
    field :join_code, :string
    field :archived_at, :utc_datetime_usec

    belongs_to :assignment, Assignment
    belongs_to :created_by, User
    has_many :members, TeamMember

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(team, attrs) do
    team
    |> cast(attrs, [:name, :join_code, :assignment_id, :created_by_id])
    |> validate_required([:name, :assignment_id, :created_by_id])
    |> validate_length(:name, min: 1, max: 120)
    |> unique_constraint(:name, name: "assignment_teams_assignment_id_name_index")
    |> unique_constraint(:join_code)
    |> foreign_key_constraint(:assignment_id)
    |> foreign_key_constraint(:created_by_id)
  end
end
