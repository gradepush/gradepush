defmodule GradePush.Assignments.AssignmentTest do
  use Ecto.Schema
  import Ecto.Changeset

  alias GradePush.Assignments.Assignment

  @runtimes ~w(system python-3.14.7 node-24.21.0 php-8.5.11 java-25 c-cpp-14)

  schema "assignment_tests" do
    field :name, :string
    field :description, :string, default: ""
    field :type, :string
    field :points, :integer
    field :timeout_seconds, :integer, default: 300
    field :output_comparison, :string, default: "trim_trailing"
    field :runtime, :string, default: "system"
    field :setup_command, :string, default: ""
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
      :output_comparison,
      :runtime,
      :setup_command,
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
    |> validate_options()
    |> validate_type_fields()
    |> foreign_key_constraint(:assignment_id)
  end

  def validate_options(changeset) do
    changeset
    |> validate_required([:output_comparison, :runtime])
    |> validate_inclusion(:output_comparison, ~w(exact trim_trailing contains regex))
    |> validate_length(:setup_command, max: 100_000, count: :bytes)
    |> validate_length(:command, max: 100_000, count: :bytes)
    |> validate_length(:input, max: 100_000, count: :bytes)
    |> validate_length(:expected,
      max: if(get_field(changeset, :output_comparison) == "regex", do: 4_096, else: 100_000),
      count: :bytes
    )
    |> validate_change(:runtime, fn :runtime, value ->
      if valid_runtime?(value), do: [], else: [runtime: "is invalid"]
    end)
  end

  def valid_runtime?(value), do: value in @runtimes

  defp validate_type_fields(changeset) do
    case get_field(changeset, :type) do
      "command" -> validate_required(changeset, [:command])
      "file" -> validate_required(changeset, [:path])
      "io" -> validate_required(changeset, [:command, :expected])
      _ -> changeset
    end
  end
end
