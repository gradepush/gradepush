defmodule GradePush.GitHub.Actions do
  @moduledoc """
  Builds a least-privilege GitHub Actions workflow from teacher-authored test settings.

  These results are formative. A repository writer can change the workflow and test files, so the
  workflow definition must be checked against its recorded blob SHA before accepting a score.
  """

  @workflow_path ".github/workflows/gradepush.yml"
  @checkout "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"

  def workflow_path, do: @workflow_path

  def generate_workflow(tests) when is_list(tests) and tests != [] do
    with :ok <- validate_tests(tests) do
      jobs = Enum.map_join(tests, "\n", &job/1)

      {:ok,
       """
       # gradepush:managed-workflow:v1
       name: GradePush autograding
       "on":
         push: {}
       permissions:
         contents: read
       jobs:
       #{jobs}
       """}
    end
  end

  def generate_workflow(_), do: {:error, :no_autograding_tests}

  def job_results(jobs, tests) when is_list(jobs) and is_list(tests) do
    test_by_id = Map.new(tests, &{normalized_id(field(&1, :id)), &1})

    matching_jobs =
      jobs
      |> Enum.reduce(%{}, fn job, matches ->
        with %{"id" => id} <- job_id(job["name"]),
             test when not is_nil(test) <- Map.get(test_by_id, id),
             false <- Map.has_key?(matches, id) do
          status = status(job["conclusion"])
          max_points = field(test, :points) || 0

          Map.put(matches, id, %{
            test_id: field(test, :id),
            name: field(test, :name),
            status: status,
            points_awarded: if(status == "success", do: max_points, else: 0),
            max_points: max_points
          })
        else
          _ -> matches
        end
      end)

    expected_ids = Map.keys(test_by_id) |> MapSet.new()
    found_ids = Map.keys(matching_jobs) |> MapSet.new()
    results = expected_ids |> Enum.flat_map(&List.wrap(Map.get(matching_jobs, &1)))
    score = Enum.reduce(results, 0, &(&1.points_awarded + &2))
    max_score = Enum.reduce(results, 0, &(&1.max_points + &2))

    if MapSet.equal?(expected_ids, found_ids) and map_size(test_by_id) == length(tests),
      do: {:ok, %{tests: results, score: score, max_score: max_score}},
      else: {:error, :incomplete_workflow_results}
  end

  def workflow_status("success"), do: "success"
  def workflow_status("failure"), do: "failure"
  def workflow_status("cancelled"), do: "cancelled"
  def workflow_status("timed_out"), do: "failure"
  def workflow_status(_), do: "in_progress"

  defp validate_tests(tests) do
    valid? =
      length(tests) <= 100 and
        unique_test_ids?(tests) and Enum.all?(tests, &valid_test?/1)

    if valid?, do: :ok, else: {:error, :invalid_autograding_tests}
  end

  defp unique_test_ids?(tests),
    do: length(Enum.uniq_by(tests, &normalized_id(field(&1, :id)))) == length(tests)

  defp valid_test?(test) do
    positive_id?(field(test, :id)) and
      valid_text?(field(test, :name), 100) and
      field(test, :type) in ["command", "file", "io"] and
      valid_timeout?(field(test, :timeout_seconds)) and
      valid_points?(field(test, :points)) and
      valid_test_fields?(test)
  end

  defp valid_timeout?(seconds), do: is_integer(seconds) and seconds in 30..1200
  defp valid_points?(points), do: is_integer(points) and points in 1..1000

  defp valid_test_fields?(test) do
    case field(test, :type) do
      "command" ->
        valid_text?(field(test, :command), 100_000)

      "file" ->
        valid_file_path?(field(test, :path))

      "io" ->
        valid_text?(field(test, :command), 100_000) and
          valid_text?(field(test, :input) || "", 100_000) and
          valid_text?(field(test, :expected), 100_000)
    end
  end

  defp job(test) do
    id = field(test, :id)
    name = "GradePush test [gp-test-#{id}] #{field(test, :name)}" |> yaml_string()
    steps = step_script(test)
    timeout = div(field(test, :timeout_seconds) + 59, 60) + 5

    [
      "  test_#{id}:\n",
      "    name: #{name}\n",
      "    runs-on: ubuntu-latest\n",
      "    timeout-minutes: #{timeout}\n",
      "    steps:\n",
      "      - uses: #{@checkout}\n",
      "        with:\n",
      "          persist-credentials: false\n",
      "      - name: Run test\n",
      "        shell: bash\n",
      "        run: |\n",
      indent(steps, 10),
      "\n"
    ]
    |> IO.iodata_to_binary()
  end

  defp step_script(%{type: "command"} = test), do: command_script(field(test, :command), test)
  defp step_script(%{"type" => "command"} = test), do: command_script(field(test, :command), test)

  defp step_script(%{type: "file"} = test), do: file_script(field(test, :path))
  defp step_script(%{"type" => "file"} = test), do: file_script(field(test, :path))

  defp step_script(%{type: "io"} = test), do: io_script(test)
  defp step_script(%{"type" => "io"} = test), do: io_script(test)

  defp command_script(command, test) do
    """
    set -euo pipefail
    printf '%s' '#{encode(command)}' | base64 --decode > "$RUNNER_TEMP/gradepush-test.sh"
    timeout --signal=TERM --kill-after=5s #{field(test, :timeout_seconds)}s bash "$RUNNER_TEMP/gradepush-test.sh"
    """
  end

  defp file_script(path) do
    """
    set -euo pipefail
    path="$(printf '%s' '#{encode(path)}' | base64 --decode)"
    test -e "$path"
    """
  end

  defp io_script(test) do
    """
    set -euo pipefail
    printf '%s' '#{encode(field(test, :command))}' | base64 --decode > "$RUNNER_TEMP/gradepush-test.sh"
    printf '%s' '#{encode(field(test, :input) || "")}' | base64 --decode > "$RUNNER_TEMP/gradepush-input"
    printf '%s' '#{encode(field(test, :expected))}' | base64 --decode > "$RUNNER_TEMP/gradepush-expected"
    set +e
    timeout --signal=TERM --kill-after=5s #{field(test, :timeout_seconds)}s bash "$RUNNER_TEMP/gradepush-test.sh" < "$RUNNER_TEMP/gradepush-input" > "$RUNNER_TEMP/gradepush-actual"
    result=$?
    set -e
    test "$result" -eq 0
    cmp -s "$RUNNER_TEMP/gradepush-expected" "$RUNNER_TEMP/gradepush-actual"
    """
  end

  defp job_id(name) when is_binary(name) do
    case Regex.run(~r/\[gp-test-([1-9][0-9]*)\]/, name, capture: :all_but_first) do
      [id] -> %{"id" => id}
      _ -> nil
    end
  end

  defp job_id(_), do: nil

  defp normalized_id(id) when is_integer(id) and id > 0, do: Integer.to_string(id)
  defp normalized_id(id) when is_binary(id), do: String.trim(id)
  defp normalized_id(_), do: nil

  defp status("success"), do: "success"
  defp status("cancelled"), do: "cancelled"
  defp status("skipped"), do: "skipped"
  defp status(_), do: "failure"

  defp indent(text, spaces) do
    prefix = String.duplicate(" ", spaces)
    text |> String.trim_trailing() |> String.split("\n") |> Enum.map_join("\n", &(prefix <> &1))
  end

  defp yaml_string(value), do: Jason.encode!(value)
  defp encode(value), do: value |> to_string() |> Base.encode64()
  defp valid_text?(value, max), do: is_binary(value) and byte_size(value) <= max

  defp valid_file_path?(path) do
    is_binary(path) and String.trim(path) != "" and byte_size(path) <= 500 and
      Path.type(path) == :relative and not Enum.member?(Path.split(path), "..")
  end

  defp positive_id?(value) when is_integer(value), do: value > 0

  defp positive_id?(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> id > 0
      _ -> false
    end
  end

  defp positive_id?(_), do: false

  defp field(test, key), do: Map.get(test, key) || Map.get(test, Atom.to_string(key))
end
