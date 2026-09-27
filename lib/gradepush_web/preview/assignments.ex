defmodule GradePushWeb.Preview.Assignments do
  @moduledoc "Builds simulated assignment records and submission results for the teacher preview."
  use Gettext, backend: GradePushWeb.Gettext

  alias GradePushWeb.Preview.{AssignmentContent, Fixtures}

  def details(assignment, classroom, query, filter, locale) do
    tests =
      assignment
      |> tests()
      |> Enum.map(fn test ->
        test
        |> Map.put_new_lazy(:name, fn -> AssignmentContent.test_name(test.key) end)
        |> Map.put_new_lazy(:description, fn -> AssignmentContent.test_description(test.key) end)
      end)

    rows =
      assignment
      |> rows(classroom)
      |> visible_rows(query, filter)
      |> Enum.map(&Map.put(&1, :score, score(assignment, &1)))

    instructions =
      if assignment[:instructions],
        do: Map.fetch!(assignment.instructions, String.to_existing_atom(locale)),
        else: AssignmentContent.instructions(assignment.key)

    %{
      rows: rows,
      tests: tests,
      dates: activity_dates(assignment),
      total_points: Enum.sum_by(tests, & &1.points),
      instructions: instructions
    }
  end

  def for_classroom(slug) do
    Fixtures.assignments()
    |> Enum.map(fn assignment ->
      key = assignment.key

      Map.merge(assignment, %{
        key: key,
        group?: key in ~w(functions linked-list),
        tests?: key == "cli"
      })
    end)
    |> Enum.filter(&(&1.classroom == slug))
  end

  def find(classroom, key), do: Enum.find(for_classroom(classroom), &(&1.key == key))

  def rows(assignment, classroom) do
    if assignment.group? do
      classroom.members
      |> Enum.take(assignment.submitted)
      |> Enum.chunk_every(2)
      |> Enum.with_index()
      |> Enum.map(fn {members, index} ->
        member = hd(members)

        row(assignment, member, index)
        |> Map.merge(%{
          key: "team-#{index + 1}",
          name: gettext("Team %{number}", number: index + 1),
          members: Enum.map_join(members, ", ", & &1.name),
          member_profiles: members,
          search_terms: Enum.map_join(members, " ", &"#{&1.name} #{&1.identifier} #{&1.handle}"),
          repository: "#{assignment.key}-team-#{index + 1}"
        })
      end)
    else
      Enum.with_index(classroom.members, fn member, index -> row(assignment, member, index) end)
    end
  end

  def visible_rows(rows, query, filter) do
    Enum.filter(rows, fn row ->
      search = Enum.join([row.name, row.handle, row.identifier, row[:search_terms]], " ")

      String.contains?(String.downcase(search), String.downcase(query)) and
        (filter == "all" or Atom.to_string(row.status) == filter)
    end)
  end

  defp row(assignment, member, index) do
    status = status(assignment, index)

    scored? =
      status in [:pushed, :late] and assignment.tests? and
        not Map.get(assignment, :scores_pending?, false)

    Map.merge(member, %{
      key: member.handle,
      status: status,
      repository: if(status != :not_accepted, do: "#{assignment.key}-#{member.handle}"),
      pushed: push_time(assignment, status, index),
      checks: if(scored?, do: rem(index, 5)),
      activity: activity(assignment, status, index)
    })
  end

  def tests(%{test_specs: tests}), do: tests
  def tests(%{tests?: false}), do: []

  def tests(_assignment) do
    [
      %{key: :help, points: 10},
      %{key: :missing, points: 20},
      %{key: :unknown, points: 30},
      %{key: :quoted, points: 40}
    ]
  end

  def score(_assignment, %{checks: nil}), do: nil

  def score(assignment, row),
    do: assignment |> tests() |> Enum.take(row.checks) |> Enum.sum_by(& &1.points)

  def activity_dates(assignment) do
    last = if assignment.key == "loops", do: ~D[2026-09-19], else: ~D[2026-09-25]
    Enum.map(-13..0, &Date.add(last, &1))
  end

  defp activity(_assignment, status, _index) when status in [:not_accepted, :no_push], do: []

  defp activity(assignment, status, index) do
    counts =
      case rem(index, 4) do
        0 -> [0, 1, 0, 2, 1, 0, 3, 2, 0, 1, 2, 0, 2, 1]
        1 -> [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]
        2 -> [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 4, 6, 3]
        3 -> [1, 2, 0, 1, 0, 2, 1, 2, 0, 3, 1, 1, 2, 2]
      end

    if assignment.key == "loops" and status != :late,
      do: Enum.drop(counts, 1) ++ [0],
      else: counts
  end

  defp status(assignment, index) do
    cond do
      index >= assignment.submitted -> :not_accepted
      rem(index, 7) == 6 -> :no_push
      assignment.key == "loops" and index in [1, 4] -> :late
      true -> :pushed
    end
  end

  defp push_time(_assignment, status, _index) when status in [:not_accepted, :no_push], do: nil

  defp push_time(assignment, status, index) do
    day = if assignment.key == "loops", do: if(status == :late, do: 19, else: 18), else: 25
    time = if rem(index, 2) == 0, do: "14:32", else: "10:08"
    %{en: "Sep #{day}, #{time}", fr: "#{day} sept., #{time}"}
  end
end
