defmodule GradePush.Assignments.Assignment do
  use Ecto.Schema
  import Ecto.Changeset

  alias GradePush.Assignments.{AssignmentTest, Subject, Team}
  alias GradePush.Classrooms.Classroom

  schema "assignments" do
    field :slug, :string
    field :title, :string
    field :instructions, :string, default: ""
    field :kind, :string, default: "individual"
    field :team_mode, :string, default: "students"
    field :team_size, :integer, default: 2
    field :deadline_at, :utc_datetime_usec
    field :cutoff_enabled, :boolean, default: false
    field :template_repository, :string
    field :repository_name_pattern, :string, default: "{classroom}-{assignment}-{identifier}"
    field :repository_visibility, :string, default: "private"
    field :autograding_enabled, :boolean, default: false
    field :published_at, :utc_datetime_usec
    field :archived_at, :utc_datetime_usec
    field :submissions_count, :integer, virtual: true, default: 0

    belongs_to :classroom, Classroom
    has_many :tests, AssignmentTest
    has_many :teams, Team
    has_many :subjects, Subject

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(assignment, attrs) do
    assignment
    |> cast(attrs, [
      :slug,
      :title,
      :instructions,
      :kind,
      :team_mode,
      :team_size,
      :deadline_at,
      :cutoff_enabled,
      :template_repository,
      :repository_name_pattern,
      :repository_visibility,
      :autograding_enabled,
      :published_at,
      :archived_at
    ])
    |> validate_required([:title, :kind, :team_mode, :repository_visibility])
    |> validate_length(:title, min: 1, max: 120)
    |> validate_length(:instructions, max: 20_000)
    |> validate_length(:template_repository, max: 255)
    |> validate_length(:repository_name_pattern, min: 1, max: 180)
    |> validate_inclusion(:kind, ~w(individual team))
    |> validate_inclusion(:team_mode, ~w(students teacher))
    |> validate_inclusion(:repository_visibility, ~w(private public))
    |> validate_number(:team_size, greater_than_or_equal_to: 2, less_than_or_equal_to: 20)
    |> validate_cutoff()
    |> unique_constraint([:classroom_id, :slug])
    |> foreign_key_constraint(:classroom_id)
  end

  defp validate_cutoff(changeset) do
    if get_field(changeset, :cutoff_enabled) and is_nil(get_field(changeset, :deadline_at)) do
      add_error(changeset, :cutoff_enabled, "requires a deadline")
    else
      changeset
    end
  end
end
