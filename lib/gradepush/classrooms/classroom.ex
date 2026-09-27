defmodule GradePush.Classrooms.Classroom do
  use Ecto.Schema
  import Ecto.Changeset

  alias GradePush.Assignments.Assignment
  alias GradePush.Classrooms.{ClassroomStudent, ClassroomTeacher, GitHubConnection}

  schema "classrooms" do
    field :slug, :string
    field :title, :string
    field :code, :string, default: ""
    field :description, :string, default: ""
    field :session, :string, default: ""
    field :semester, :string
    field :academic_year, :integer
    field :archived_at, :utc_datetime_usec
    field :students_count, :integer, virtual: true, default: 0
    field :assignments_count, :integer, virtual: true, default: 0
    field :teachers_count, :integer, virtual: true, default: 0

    belongs_to :created_by, GradePush.Accounts.User
    belongs_to :github_connection, GitHubConnection
    has_many :teachers, ClassroomTeacher
    has_many :students, ClassroomStudent
    has_many :assignments, Assignment

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(classroom, attrs) do
    classroom
    |> cast(attrs, [
      :slug,
      :title,
      :code,
      :description,
      :session,
      :semester,
      :academic_year,
      :github_connection_id
    ])
    |> validate_required([:title, :github_connection_id])
    |> validate_length(:title, min: 1, max: 160)
    |> validate_length(:code, max: 80)
    |> validate_length(:description, max: 4_000)
    |> validate_length(:session, max: 120)
    |> validate_inclusion(:semester, ~w(winter summer fall))
    |> validate_number(:academic_year,
      greater_than_or_equal_to: 1900,
      less_than_or_equal_to: 9999
    )
    |> validate_term_pair()
    |> check_constraint(:academic_year, name: :classroom_term_check)
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:github_connection_id)
  end

  defp validate_term_pair(changeset) do
    semester = get_field(changeset, :semester)
    academic_year = get_field(changeset, :academic_year)

    if is_nil(semester) == is_nil(academic_year) do
      changeset
    else
      add_error(changeset, :academic_year, "must be set together with the semester")
    end
  end
end
