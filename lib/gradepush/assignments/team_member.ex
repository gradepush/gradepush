defmodule GradePush.Assignments.TeamMember do
  use Ecto.Schema

  alias GradePush.Accounts.User
  alias GradePush.Assignments.Team

  schema "assignment_team_members" do
    field :left_at, :utc_datetime_usec
    belongs_to :team, Team
    belongs_to :assignment, GradePush.Assignments.Assignment
    belongs_to :user, User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
