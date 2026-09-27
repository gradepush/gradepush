defmodule GradePushWeb.Preview.AssignmentEditing do
  @moduledoc "Converts assignment forms to in-memory preview records without GitHub or database writes."
  alias GradePushWeb.Forms.AssignmentDraft
  alias GradePushWeb.Preview.AssignmentContent
  alias GradePushWeb.Preview.Assignments

  def templates(classroom) do
    Enum.map(~w(python-starter c-starter web-starter), &"#{classroom.organization}/#{&1}") ++
      Enum.map(Assignments.for_classroom(classroom.slug), & &1.repository)
  end

  def params(nil, _locale), do: %{}

  def params(assignment, locale) do
    Map.get_lazy(assignment, :editor_params, fn ->
      %{
        "title" => local(assignment.title, locale),
        "instructions" => AssignmentContent.instructions(assignment.key),
        "deadline" => deadline(assignment.key),
        "cutoff" => "false",
        "template" => assignment.repository,
        "kind" => if(assignment.group?, do: "team", else: "individual"),
        "team_mode" => "students",
        "team_size" => "2",
        "autograding" => to_string(assignment.tests?),
        "tests" => assignment |> Assignments.tests() |> Enum.map(&test_params/1)
      }
    end)
  end

  def changeset(params, assignment, classroom, locale) do
    params = lock_repository(params, assignment, locale)
    AssignmentDraft.changeset(%AssignmentDraft{}, params, templates(classroom))
  end

  def add_test(params) do
    Map.put(params, "tests", tests(params) ++ [%{"type" => "command", "points" => "10"}])
  end

  def remove_test(params, index),
    do: Map.put(params, "tests", List.delete_at(tests(params), index))

  def materialize(draft, existing, classroom, key) do
    tests = if draft.autograding, do: Enum.map(draft.tests, &test_data/1), else: []
    original_tests = original_tests(existing, classroom)

    Map.merge(existing || %{}, %{
      key: key,
      classroom: classroom.slug,
      title: both(draft.title),
      instructions: both(draft.instructions || ""),
      due:
        both(
          if draft.deadline, do: Calendar.strftime(draft.deadline, "%Y-%m-%d · %H:%M"), else: ""
        ),
      status: if(draft.deadline, do: :open, else: :draft),
      kind:
        if(draft.kind == "team",
          do: %{en: "Team", fr: "En équipe"},
          else: %{en: "Individual", fr: "Individuel"}
        ),
      group?: draft.kind == "team",
      team_mode: draft.team_mode,
      team_size: draft.team_size,
      cutoff: draft.cutoff,
      tests?: draft.autograding,
      test_specs: tests,
      scores_pending?: scores_pending?(existing, tests, original_tests),
      repository: draft.template,
      submitted: if(existing, do: existing.submitted, else: 0),
      total: classroom.students,
      editor_params: to_params(draft)
    })
  end

  defp scores_pending?(nil, _tests, _original_tests), do: false

  defp scores_pending?(existing, tests, original_tests),
    do:
      Map.get(existing, :scores_pending?, false) or
        scoring_specs(tests) != scoring_specs(original_tests)

  defp scoring_specs(tests), do: Enum.map(tests, &Map.drop(&1, [:name, :description]))

  defp original_tests(nil, _classroom), do: []

  defp original_tests(assignment, classroom) do
    locale = Gettext.get_locale(GradePushWeb.Gettext)

    assignment
    |> params(locale)
    |> changeset(assignment, classroom, locale)
    |> Ecto.Changeset.apply_changes()
    |> Map.fetch!(:tests)
    |> Enum.map(&test_data/1)
  end

  defp to_params(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp to_params(%_{} = value), do: value |> Map.from_struct() |> to_params()

  defp to_params(value) when is_map(value),
    do: Map.new(value, fn {key, val} -> {to_string(key), to_params(val)} end)

  defp to_params(value) when is_list(value), do: Enum.map(value, &to_params/1)
  defp to_params(value), do: value

  defp lock_repository(params, nil, _locale), do: params

  defp lock_repository(params, assignment, locale) do
    if assignment.submitted > 0 do
      Map.merge(
        params,
        Map.take(params(assignment, locale), ~w(template kind team_mode team_size))
      )
    else
      params
    end
  end

  defp tests(%{"tests" => tests}) when is_list(tests), do: tests

  defp tests(%{"tests" => tests}) when is_map(tests),
    do: tests |> Enum.sort_by(fn {key, _} -> String.to_integer(key) end) |> Enum.map(&elem(&1, 1))

  defp tests(_), do: []

  defp test_params(test) do
    %{
      "name" => AssignmentContent.test_name(test.key),
      "description" => AssignmentContent.test_description(test.key),
      "type" => "command",
      "points" => to_string(test.points),
      "command" => "python -m unittest tests.test_cli.TestCLI.test_#{test.key}"
    }
  end

  defp test_data(test), do: Map.from_struct(test)

  defp deadline("cli"), do: "2026-09-30T23:59"
  defp deadline("loops"), do: "2026-09-18T23:59"
  defp deadline("portfolio"), do: "2026-10-02T23:59"
  defp deadline("linked-list"), do: "2026-10-06T23:59"
  defp deadline(_), do: ""
  defp both(value), do: %{en: value, fr: value}
  defp local(value, locale), do: Map.fetch!(value, String.to_existing_atom(locale))
end
