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

    name =
      "GradePush test [gp-test-#{id}] #{field(test, :name)}" |> safe_display() |> yaml_string()

    step_name = step_name(test) |> safe_display() |> yaml_string()
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
      "      - name: #{step_name}\n",
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

  defp step_name(%{type: "command"} = test), do: "Run command test: #{field(test, :name)}"
  defp step_name(%{"type" => "command"} = test), do: "Run command test: #{field(test, :name)}"
  defp step_name(%{type: "file"} = test), do: "Check required file: #{field(test, :path)}"
  defp step_name(%{"type" => "file"} = test), do: "Check required file: #{field(test, :path)}"

  defp step_name(%{type: "io"} = test),
    do: "Check program input and output: #{field(test, :name)}"

  defp step_name(%{"type" => "io"} = test),
    do: "Check program input and output: #{field(test, :name)}"

  defp command_script(command, test) do
    """
    set -euo pipefail
    script_file="$RUNNER_TEMP/gradepush-test.sh"
    timeout_seconds=#{field(test, :timeout_seconds)}
    printf '%s' '#{encode(command)}' | base64 --decode > "$script_file"
    #{suspend_workflow_commands()}
    printf 'Command source:\\n'
    cat "$script_file"
    printf '\\nCommand output:\\n'
    set +e
    timeout --signal=TERM --kill-after=5s "${timeout_seconds}s" bash "$script_file"
    result=$?
    set -e
    #{resume_workflow_commands()}
    #{report_result()}
    """
  end

  defp file_script(path) do
    """
    set -euo pipefail
    path="$(printf '%s' '#{encode(path)}' | base64 --decode)"
    #{suspend_workflow_commands()}
    printf 'Required file: %s\\n' "$path"
    if [ -e "$path" ]; then result=0; else result=1; fi
    #{resume_workflow_commands()}
    if [ "$result" -eq 0 ]; then
      printf 'PASS: required file exists.\\n'
    else
      printf 'FAIL: required file is missing.\\n'
      exit 1
    fi
    """
  end

  defp io_script(test) do
    """
    set -euo pipefail
    script_file="$RUNNER_TEMP/gradepush-test.sh"
    input_file="$RUNNER_TEMP/gradepush-input"
    expected_file="$RUNNER_TEMP/gradepush-expected"
    actual_file="$RUNNER_TEMP/gradepush-actual"
    stderr_file="$RUNNER_TEMP/gradepush-stderr"
    diff_file="$RUNNER_TEMP/gradepush-diff"
    timeout_seconds=#{field(test, :timeout_seconds)}
    printf '%s' '#{encode(field(test, :command))}' | base64 --decode > "$script_file"
    printf '%s' '#{encode(field(test, :input) || "")}' | base64 --decode > "$input_file"
    printf '%s' '#{encode(field(test, :expected))}' | base64 --decode > "$expected_file"
    show_preview() {
      file="$1"
      size="$(wc -c < "$file" | tr -d '[:space:]')"
      head -c 32768 "$file"
      printf '\\n'
      if [ "$size" -gt 32768 ]; then
        printf '[Preview truncated after 32768 bytes; %s bytes total.]\\n' "$size"
      fi
    }
    #{suspend_workflow_commands()}
    printf 'Command source:\\n'
    show_preview "$script_file"
    printf '\\nProgram input:\\n'
    show_preview "$input_file"
    printf '\\nExpected output:\\n'
    show_preview "$expected_file"
    printf '\\nActual output:\\n'
    set +e
    timeout --signal=TERM --kill-after=5s "${timeout_seconds}s" bash "$script_file" < "$input_file" > "$actual_file" 2> "$stderr_file"
    result=$?
    set -e
    show_preview "$actual_file"
    if [ -s "$stderr_file" ]; then
      printf '\\nProgram error output:\\n'
      show_preview "$stderr_file"
    fi
    if cmp -s "$expected_file" "$actual_file"; then matches=true; else matches=false; fi
    if [ "$matches" = false ]; then
      diff -u --label 'Expected output' --label 'Actual output' "$expected_file" "$actual_file" > "$diff_file" || true
      printf '\\nOutput difference:\\n'
      show_preview "$diff_file"
    fi
    #{resume_workflow_commands()}
    if [ "$result" -eq 124 ]; then
      printf 'FAIL: test timed out after %s seconds.\\n' "$timeout_seconds"
      exit 1
    elif [ "$result" -ne 0 ]; then
      printf 'FAIL: test command exited with code %s.\\n' "$result"
      exit 1
    elif [ "$matches" = false ]; then
      printf 'FAIL: actual output did not match expected output.\\n'
      exit 1
    else
      printf 'PASS: actual output matched expected output.\\n'
    fi
    """
  end

  defp suspend_workflow_commands do
    """
    workflow_command_token="$(od -An -N32 -tx1 /dev/urandom | tr -d '[:space:]')"
    printf '::stop-commands::%s\\n' "$workflow_command_token"
    """
  end

  defp resume_workflow_commands,
    do: "printf '\\n::%s::\\n' \"$workflow_command_token\""

  defp report_result do
    """
    if [ "$result" -eq 0 ]; then
      printf 'PASS: command completed with exit code 0.\\n'
    elif [ "$result" -eq 124 ]; then
      printf 'FAIL: command timed out after %s seconds.\\n' "$timeout_seconds"
      exit 1
    else
      printf 'FAIL: command exited with code %s.\\n' "$result"
      exit 1
    fi
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
  defp safe_display(value), do: String.replace(value, "${{", "$ { {")
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
