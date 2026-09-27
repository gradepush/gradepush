defmodule GradePush.Assignments.Subject do
  use Ecto.Schema
  import Ecto.Changeset

  alias GradePush.Accounts.User
  alias GradePush.Assignments.{Assignment, Team}
  alias GradePush.Assignments.Repository
  alias GradePush.Submissions.{Grade, Push}

  schema "assignment_subjects" do
    field :kind, :string
    field :accepted_at, :utc_datetime_usec
    field :extension_until, :utc_datetime_usec
    field :latest_push, :any, virtual: true
    field :latest_grade, :any, virtual: true

    belongs_to :assignment, Assignment
    belongs_to :user, User
    belongs_to :team, Team
    has_one :repository, Repository
    has_many :pushes, Push
    has_many :grades, Grade

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(subject, attrs) do
    subject
    |> cast(attrs, [:kind, :accepted_at, :assignment_id, :user_id, :team_id, :extension_until])
    |> validate_required([:kind, :accepted_at, :assignment_id])
    |> validate_inclusion(:kind, ~w(individual team))
    |> foreign_key_constraint(:assignment_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:team_id)
    |> unique_constraint([:assignment_id, :user_id])
    |> unique_constraint([:assignment_id, :team_id])
  end
end
