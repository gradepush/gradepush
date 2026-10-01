defmodule GradePush.GitHub.Actions do
  @moduledoc """
  Builds a least-privilege GitHub Actions workflow from teacher-authored test settings.

  These results are formative. A repository writer can change the workflow and test files, so the
  workflow definition must be checked against its recorded blob SHA before accepting a score.
  """

  alias GradePush.Assignments.AssignmentTest

  @workflow_path ".github/workflows/gradepush.yml"
  @checkout "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
  @setup_python "actions/setup-python@5fda3b95a4ea91299a34e894583c3862153e4b97"
  @setup_node "actions/setup-node@820762786026740c76f36085b0efc47a31fe5020"
  @setup_php "shivammathur/setup-php@f3e473d116dcccaddc5834248c87452386958240"

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
      valid_text?(field(test, :name), 120) and
      field(test, :type) in ["command", "file", "io"] and
      valid_timeout?(field(test, :timeout_seconds)) and
      valid_points?(field(test, :points)) and
      valid_options?(test) and
      valid_test_fields?(test)
  end

  defp valid_options?(test),
    do:
      comparison(test) in ~w(exact trim_trailing contains regex) and
        AssignmentTest.valid_runtime?(runtime(test)) and
        valid_text?(field(test, :setup_command) || "", 100_000)

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
          valid_text?(
            field(test, :expected),
            if(comparison(test) == "regex", do: 4_096, else: 100_000)
          )
    end
  end

  defp job(test) do
    id = field(test, :id)

    name =
      "GradePush test [gp-test-#{id}] #{field(test, :name)}" |> safe_display() |> yaml_string()

    step_name = step_name(test) |> safe_display() |> yaml_string()
    steps = step_script(test)
    commands = if preparation?(test), do: 2, else: 1
    timeout = commands * div(field(test, :timeout_seconds) + 59, 60) + 5

    [
      "  test_#{id}:\n",
      "    name: #{name}\n",
      "    runs-on: ubuntu-24.04\n",
      "    timeout-minutes: #{timeout}\n",
      "    steps:\n",
      "      - uses: #{@checkout}\n",
      "        with:\n",
      "          persist-credentials: false\n",
      runtime_steps(runtime(test)),
      preparation_step(test),
      "      - name: #{step_name}\n",
      "        shell: bash\n",
      "        run: |\n",
      indent(steps, 10),
      "\n"
    ]
    |> IO.iodata_to_binary()
  end

  defp runtime(test), do: field(test, :runtime) || "system"
  defp comparison(test), do: field(test, :output_comparison) || "trim_trailing"

  defp runtime_steps("system"), do: ""

  defp runtime_steps("java-25") do
    """
          - name: Select Java 25
            shell: bash
            run: |
              test -x "$JAVA_HOME_25_X64/bin/javac"
              printf 'JAVA_HOME=%s\\n' "$JAVA_HOME_25_X64" >> "$GITHUB_ENV"
              printf '%s/bin\\n' "$JAVA_HOME_25_X64" >> "$GITHUB_PATH"
    """
  end

  defp runtime_steps("c-cpp-14") do
    """
          - name: Select GCC 14
            shell: bash
            run: |
              test -x /usr/bin/gcc-14 && test -x /usr/bin/g++-14
              tools="$RUNNER_TEMP/gradepush-compiler"
              mkdir -p "$tools"
              ln -s /usr/bin/gcc-14 "$tools/gcc"
              ln -s /usr/bin/g++-14 "$tools/g++"
              printf '%s\\n' "$tools" >> "$GITHUB_PATH"
              printf 'CC=gcc-14\\nCXX=g++-14\\n' >> "$GITHUB_ENV"
    """
  end

  defp runtime_steps(runtime) do
    [language, version] = String.split(runtime, "-", parts: 2)

    {action, version_key, options} =
      case language do
        "python" -> {@setup_python, "python-version", ""}
        "node" -> {@setup_node, "node-version", "          package-manager-cache: false\n"}
        "php" -> {@setup_php, "php-version", "          coverage: none\n          tools: none\n"}
      end

    "      - uses: #{action}\n        with:\n          #{version_key}: #{yaml_string(version)}\n#{options}"
  end

  defp preparation?(test),
    do: field(test, :type) != "file" and String.trim(field(test, :setup_command) || "") != ""

  defp preparation_step(test) do
    if preparation?(test) do
      "      - name: Prepare project\n        shell: bash\n        run: |\n" <>
        indent(command_script(field(test, :setup_command), test), 10) <> "\n"
    else
      ""
    end
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
    (ulimit -f 8193; timeout --signal=TERM --kill-after=5s "${timeout_seconds}s" bash "$script_file" < "$input_file" > "$actual_file" 2> "$stderr_file")
    result=$?
    set -e
    if [ "$(wc -c < "$actual_file")" -gt 8388608 ] || [ "$(wc -c < "$stderr_file")" -gt 8388608 ]; then result=153; fi
    show_preview "$actual_file"
    if [ -s "$stderr_file" ]; then
      printf '\\nProgram error output:\\n'
      show_preview "$stderr_file"
    fi
    matches=false
    comparison_result=0
    if [ "$result" -eq 0 ]; then
    #{compare_output(test)}
    fi
    if [ "$result" -eq 0 ] && [ "$comparison_result" -eq 0 ] && [ "$matches" = false ] && [ '#{comparison(test)}' != regex ]; then
      diff -u --label 'Expected output' --label 'Actual output' "$expected_file" "$actual_file" > "$diff_file" || true
      printf '\\nOutput difference:\\n'
      show_preview "$diff_file"
    fi
    #{resume_workflow_commands()}
    if [ "$result" -eq 124 ] || [ "$result" -eq 137 ]; then
      printf 'FAIL: test timed out after %s seconds.\\n' "$timeout_seconds"
      exit 1
    elif [ "$result" -eq 153 ]; then
      printf 'FAIL: program output exceeded the 8 MiB file limit.\\n'
      exit 1
    elif [ "$result" -ne 0 ]; then
      printf 'FAIL: test command exited with code %s.\\n' "$result"
      exit 1
    elif [ "$comparison_result" -eq 124 ] || [ "$comparison_result" -eq 137 ]; then
      printf 'FAIL: output comparison exceeded 10 seconds.\\n'
      exit 1
    elif [ "$comparison_result" -gt 1 ]; then
      printf 'FAIL: output comparison could not be completed (code %s).\\n' "$comparison_result"
      exit 1
    elif [ "$matches" = false ]; then
      printf 'FAIL: actual output did not match expected output.\\n'
      exit 1
    else
      printf 'PASS: actual output matched expected output.\\n'
    fi
    """
  end

  defp compare_output(test) do
    case comparison(test) do
      "trim_trailing" ->
        """
        normalized_expected="$RUNNER_TEMP/gradepush-expected-normalized"
        normalized_actual="$RUNNER_TEMP/gradepush-actual-normalized"
        if timeout --signal=TERM --kill-after=5s 10s python3 -I - "$expected_file" "$actual_file" "$normalized_expected" "$normalized_actual" <<'GRADE_PUSH_NORMALIZE'
        import sys

        for source, destination in zip(sys.argv[1:3], sys.argv[3:5]):
            with open(source, "rb") as incoming, open(destination, "wb") as outgoing:
                end = 0
                for line in incoming:
                    content = line.rstrip(b" \\t\\r\\n")
                    outgoing.write(content + b"\\n")
                    if content:
                        end = outgoing.tell() - 1
                outgoing.truncate(end)
        GRADE_PUSH_NORMALIZE
        then
          if cmp -s "$normalized_expected" "$normalized_actual"; then matches=true; fi
        else
          comparison_result=$?
        fi
        """

      mode when mode in ["regex", "contains"] ->
        """
        if timeout --signal=TERM --kill-after=5s 10s node --input-type=commonjs - "$expected_file" "$actual_file" '#{mode}' <<'GRADE_PUSH_COMPARE'
        const fs = require('node:fs');
        const [expectedFile, actualFile, mode] = process.argv.slice(2);
        try {
          if (fs.statSync(actualFile).size > 8 * 1024 * 1024) {
            console.log('FAIL: output comparison accepts at most 8 MiB of output.');
            process.exit(3);
          }
          const expected = fs.readFileSync(expectedFile, 'utf8');
          const actual = fs.readFileSync(actualFile, 'utf8');
          const matches = mode === 'regex' ? new RegExp(expected).test(actual) : actual.includes(expected);
          process.exit(matches ? 0 : 1);
        } catch (error) {
          console.log(error instanceof SyntaxError ? 'FAIL: invalid regular expression.' : 'FAIL: could not read output for comparison.');
          process.exit(2);
        }
        GRADE_PUSH_COMPARE
        then
          matches=true
        else
          comparison_result=$?
        fi
        """

      "exact" ->
        ~s(if cmp -s "$expected_file" "$actual_file"; then matches=true; fi)
    end
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
    elif [ "$result" -eq 124 ] || [ "$result" -eq 137 ]; then
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

    text
    |> String.trim_trailing()
    |> String.split("\n")
    |> Enum.map_join("\n", fn line -> if line == "", do: "", else: prefix <> line end)
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
