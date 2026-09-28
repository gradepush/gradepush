defmodule GradePushWeb.Forms.AssignmentDraft do
  @moduledoc false
  use Ecto.Schema
  use Gettext, backend: GradePushWeb.Gettext
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :title, :string
    field :instructions, :string, default: ""
    field :deadline, :naive_datetime
    field :cutoff, :boolean, default: false
    field :template, :string, default: ""
    field :kind, :string, default: "individual"
    field :team_mode, :string, default: "students"
    field :team_size, :integer, default: 2
    field :autograding, :boolean, default: false

    embeds_many :tests, Test, primary_key: false, on_replace: :delete do
      field :name, :string
      field :description, :string, default: ""
      field :type, :string, default: "command"
      field :points, :integer, default: 10
      field :command, :string, default: ""
      field :path, :string, default: ""
      field :input, :string, default: ""
      field :expected, :string, default: ""
    end
  end

  def changeset(draft, params, templates) do
    draft
    |> cast(
      params,
      ~w(title instructions deadline cutoff template kind team_mode team_size autograding)a
    )
    |> validate_required([:title, :kind, :team_mode, :team_size, :cutoff, :autograding])
    |> validate_length(:title, max: 120)
    |> validate_length(:instructions, max: 20_000)
    |> validate_inclusion(:kind, ~w(individual team))
    |> validate_inclusion(:team_mode, ~w(students teacher))
    |> validate_inclusion(:template, ["" | templates])
    |> validate_number(:team_size, greater_than_or_equal_to: 2, less_than_or_equal_to: 20)
    |> cast_tests()
    |> validate_grading()
    |> clear_cutoff_without_deadline()
  end

  defp cast_tests(changeset) do
    if get_field(changeset, :autograding),
      do: cast_embed(changeset, :tests, with: &test_changeset/2),
      else: put_embed(changeset, :tests, [])
  end

  defp test_changeset(test, params) do
    changeset =
      test
      |> cast(params, ~w(name description type points command path input expected)a)
      |> validate_required([:name, :type, :points])
      |> validate_length(:name, max: 120)
      |> validate_length(:description, max: 2000)
      |> validate_inclusion(:type, ~w(file command io))
      |> validate_number(:points, greater_than: 0, less_than_or_equal_to: 1000)

    case get_field(changeset, :type) do
      "file" -> validate_required(changeset, [:path])
      "io" -> validate_required(changeset, [:command, :expected])
      _ -> validate_required(changeset, [:command])
    end
  end

  defp validate_grading(changeset) do
    if get_field(changeset, :autograding) and get_field(changeset, :tests) == [] do
      add_error(changeset, :autograding, dgettext_noop("errors", "add at least one test"))
    else
      changeset
    end
  end

  defp clear_cutoff_without_deadline(changeset) do
    if get_field(changeset, :deadline), do: changeset, else: put_change(changeset, :cutoff, false)
  end
end
