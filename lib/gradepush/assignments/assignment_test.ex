defmodule GradePush.Assignments.AssignmentTest do
  use Ecto.Schema
  import Ecto.Changeset

  alias GradePush.Assignments.Assignment

  schema "assignment_tests" do
    field :name, :string
    field :description, :string, default: ""
    field :type, :string
    field :points, :integer
    field :timeout_seconds, :integer, default: 300
    field :command, :string
    field :path, :string
    field :input, :string
    field :expected, :string

    belongs_to :assignment, Assignment

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(test, attrs) do
    test
    |> cast(attrs, [
      :name,
      :description,
      :type,
      :points,
      :timeout_seconds,
      :command,
      :path,
      :input,
      :expected
    ])
    |> validate_required([:name, :type, :points, :timeout_seconds])
    |> validate_length(:name, min: 1, max: 120)
    |> validate_length(:description, max: 2_000)
    |> validate_inclusion(:type, ~w(command file io))
    |> validate_number(:points, greater_than: 0, less_than_or_equal_to: 1_000)
    |> validate_number(:timeout_seconds,
      greater_than_or_equal_to: 30,
      less_than_or_equal_to: 1_200
    )
    |> validate_type_fields()
    |> foreign_key_constraint(:assignment_id)
  end

  defp validate_type_fields(changeset) do
    case get_field(changeset, :type) do
      "command" -> validate_required(changeset, [:command])
      "file" -> validate_required(changeset, [:path])
      "io" -> validate_required(changeset, [:command, :expected])
      _ -> changeset
    end
  end
end
