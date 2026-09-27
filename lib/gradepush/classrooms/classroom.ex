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
    |> cast(attrs, [:slug, :title, :code, :description, :session, :github_connection_id])
    |> validate_required([:title, :github_connection_id])
    |> validate_length(:title, min: 1, max: 160)
    |> validate_length(:code, max: 80)
    |> validate_length(:description, max: 4_000)
    |> validate_length(:session, max: 120)
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:github_connection_id)
  end
end
