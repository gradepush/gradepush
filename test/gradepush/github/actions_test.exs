defmodule GradePush.GitHub.ActionsTest do
  use ExUnit.Case, async: true

  alias GradePush.GitHub.Actions

  test "generated workflow is read-only, pinned, and keeps commands out of YAML and shell source" do
    command = "echo safe\n$(touch /tmp/gradepush-pwned)"

    assert {:ok, workflow} =
             Actions.generate_workflow([
               %{
                 id: 1,
                 name: "Build: app",
                 type: "command",
                 command: command,
                 points: 2,
                 timeout_seconds: 60
               }
             ])

    assert workflow =~ "permissions:\n  contents: read"
    assert workflow =~ "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
    assert workflow =~ "persist-credentials: false"
    assert workflow =~ "# gradepush:managed-workflow:v1"
    assert workflow =~ "Run command test: Build: app"
    refute workflow =~ command
    refute workflow =~ "GITHUB_TOKEN"
  end

  test "expression-shaped labels are neutralized without changing file paths" do
    path = "${{ not_a_context.value }}.txt"

    assert {:ok, workflow} =
             Actions.generate_workflow([
               %{
                 id: 1,
                 name: "${{ not_a_context.value }}",
                 type: "file",
                 path: path,
                 points: 1,
                 timeout_seconds: 60
               }
             ])

    refute workflow =~ "${{"
    assert workflow =~ "$ { { not_a_context.value }}"
    script = workflow_script!(workflow)
    assert script =~ Base.encode64(path)
  end

  test "command logs show multiline shell source and output without executing quoted metacharacters" do
    with_runtime(fn runner_temp, repository, timeout_env ->
      marker = Path.join(repository, "unexpected-command-execution")

      command =
        "printf '%s\\n' 'first line'\nprintf '%s' 'literal $HOME; $(touch #{marker}); ::error::student output'"

      test = command_test(command)
      {:ok, workflow} = Actions.generate_workflow([test])
      script = workflow_script!(workflow)
      {output, status} = run_script(script, runner_temp, repository, timeout_env)

      assert status == 0
      assert output =~ command
      assert output =~ "first line"
      assert output =~ "literal $HOME; $(touch #{marker})"
      assert output =~ "::error::student output"
      assert output =~ "PASS: command completed with exit code 0."
      assert script =~ "::stop-commands::%s"
      assert script =~ "printf '\\n::%s::\\n'"

      assert :binary.match(script, "::stop-commands::%s") <
               :binary.match(script, "Command source:")

      assert :binary.match(script, "timeout --signal") <
               :binary.match(script, "printf '\\n::%s::\\n'")

      refute File.exists?(marker)
    end)
  end

  test "command failures report their exit code and timeout result" do
    with_runtime(fn runner_temp, repository, timeout_env ->
      failed = command_test("printf 'failure output\\n'; exit 7")
      {:ok, failed_workflow} = Actions.generate_workflow([failed])

      {failed_output, failed_status} =
        failed_workflow
        |> workflow_script!()
        |> run_script(runner_temp, repository, timeout_env)

      assert failed_status == 1
      assert failed_output =~ "failure output"
      assert failed_output =~ "FAIL: command exited with code 7."

      timeout = command_test("sleep 2")
      {:ok, timeout_workflow} = Actions.generate_workflow([timeout])

      timeout_script =
        timeout_workflow
        |> workflow_script!()
        |> String.replace("timeout_seconds=60", "timeout_seconds=0.1")

      timeout_env =
        if System.find_executable("timeout"),
          do: timeout_env,
          else: timeout_env ++ [{"GRADE_PUSH_FAKE_TIMEOUT", "1"}]

      {timeout_output, timeout_status} =
        run_script(timeout_script, runner_temp, repository, timeout_env)

      assert timeout_status == 1
      assert timeout_output =~ "FAIL: command timed out after 0.1 seconds."
    end)
  end

  test "IO logs show expected and actual output with a useful mismatch diff" do
    with_runtime(fn runner_temp, repository, timeout_env ->
      test = %{
        id: 1,
        name: "Greeting",
        type: "io",
        command: "read -r name; printf 'Hello, %s!\\n' \"$name\"",
        input: "Ada\n",
        expected: "Hello, Grace!\n",
        points: 1,
        timeout_seconds: 60
      }

      {:ok, workflow} = Actions.generate_workflow([test])

      {output, status} =
        workflow |> workflow_script!() |> run_script(runner_temp, repository, timeout_env)

      assert status == 1
      assert output =~ "Command source:"
      assert output =~ "Program input:"
      assert output =~ "Expected output:"
      assert output =~ "Actual output:"
      assert output =~ "Hello, Ada!"
      assert output =~ "-Hello, Grace!"
      assert output =~ "+Hello, Ada!"
      assert output =~ "FAIL: actual output did not match expected output."
    end)
  end

  test "IO previews are bounded while grading still compares the full output" do
    with_runtime(fn runner_temp, repository, timeout_env ->
      test = %{
        id: 1,
        name: "Long output",
        type: "io",
        command: ~S|awk 'BEGIN { for (i = 0; i < 40000; i++) printf "x" }'|,
        input: "",
        expected: "x",
        points: 1,
        timeout_seconds: 60
      }

      {:ok, workflow} = Actions.generate_workflow([test])

      {output, status} =
        workflow |> workflow_script!() |> run_script(runner_temp, repository, timeout_env)

      assert status == 1
      assert output =~ "[Preview truncated after 32768 bytes; 40000 bytes total.]"
      assert output =~ "FAIL: actual output did not match expected output."
    end)
  end

  test "trailing comparison preserves indentation, interior spaces and interior empty lines" do
    with_runtime(fn runner_temp, repository, timeout_env ->
      base = %{
        id: 1,
        name: "Whitespace",
        type: "io",
        points: 1,
        timeout_seconds: 60,
        input: "",
        output_comparison: "trim_trailing",
        expected: "  one two\n\nthree\n"
      }

      for {actual, expected_status} <- [
            {"  one two \t\r\n \t\nthree\t\n\n", 0},
            {"one two\n\nthree\n", 1},
            {"  one  two\n\nthree\n", 1},
            {"  one two\nthree\n", 1}
          ] do
        command = "printf '%s' '#{Base.encode64(actual)}' | base64 --decode"
        {:ok, workflow} = Actions.generate_workflow([Map.put(base, :command, command)])

        {output, status} =
          workflow |> workflow_script!() |> run_script(runner_temp, repository, timeout_env)

        assert status == expected_status
        if status == 1, do: assert(output =~ "Output difference:")
      end

      exact =
        Map.merge(base, %{output_comparison: "exact", command: "printf '  one two\\n\\nthree'"})

      {:ok, workflow} = Actions.generate_workflow([exact])

      {_, status} =
        workflow |> workflow_script!() |> run_script(runner_temp, repository, timeout_env)

      assert status == 1
    end)
  end

  test "runtime setup uses pinned actions and exact versions on a stable Ubuntu image" do
    for {runtime, action, input, version} <- [
          {"python-3.14.7", "actions/setup-python@5fda3b95a4ea91299a34e894583c3862153e4b97",
           "python-version", "3.14.7"},
          {"node-24.21.0", "actions/setup-node@820762786026740c76f36085b0efc47a31fe5020",
           "node-version", "24.21.0"},
          {"php-8.5.11", "shivammathur/setup-php@f3e473d116dcccaddc5834248c87452386958240",
           "php-version", "8.5.11"}
        ] do
      {:ok, workflow} =
        Actions.generate_workflow([Map.put(command_test("true"), :runtime, runtime)])

      assert workflow =~ "runs-on: ubuntu-24.04"
      assert workflow =~ action
      assert workflow =~ "#{input}: \"#{version}\""
      assert workflow =~ "contents: read"
    end

    {:ok, system} = Actions.generate_workflow([command_test("true")])
    assert system =~ "runs-on: ubuntu-24.04"
    refute system =~ "setup-python"

    for {runtime, executable} <- [{"java-25", "javac"}, {"c-cpp-14", "gcc-14"}] do
      {:ok, workflow} =
        Actions.generate_workflow([Map.put(command_test("true"), :runtime, runtime)])

      assert workflow =~ executable
      refute workflow =~ "docker"
      refute workflow =~ "apt-get"
    end

    for attrs <- [
          %{runtime: "python-${{ secrets.TOKEN }}"},
          %{runtime: "node-24.21.0\npermissions: write-all"},
          %{runtime: "legacy"},
          %{runtime: "python-99.0.0"},
          %{output_comparison: "unknown"}
        ] do
      assert {:error, :invalid_autograding_tests} =
               Actions.generate_workflow([Map.merge(command_test("true"), attrs)])
    end
  end

  test "preparation compiles a program, fails before running invalid code and has its own timeout" do
    with_runtime(fn runner_temp, repository, timeout_env ->
      source = "#include <stdio.h>\nint main(void) { puts(\"compiled\"); return 0; }\n"
      File.write!(Path.join(repository, "main.c"), source)
      spec = Map.put(command_test("./main"), :setup_command, "cc -Wall -Werror main.c -o main")
      {:ok, workflow} = Actions.generate_workflow([spec])
      [prepare, run] = workflow_scripts!(workflow)
      assert workflow =~ "name: Prepare project"
      assert workflow =~ "timeout-minutes: 7"
      {_, 0} = run_script(prepare, runner_temp, repository, timeout_env)
      {output, 0} = run_script(run, runner_temp, repository, timeout_env)
      assert output =~ "compiled"

      File.write!(Path.join(repository, "main.c"), "int main( { invalid C")
      {failed, 1} = run_script(prepare, runner_temp, repository, timeout_env)
      assert failed =~ "error:"
      assert failed =~ "FAIL: command exited with code"

      assert :binary.match(workflow, "name: Prepare project") <
               :binary.match(workflow, "Run command test:")
    end)
  end

  test "regex and contains comparisons support multiline output and reject invalid patterns" do
    with_runtime(fn runner_temp, repository, timeout_env ->
      base =
        Map.merge(command_test("printf 'first\\nvalue: 42\\nlast\\n'"), %{type: "io", input: ""})

      for {mode, expected, expected_status} <- [
            {"regex", "value: [0-9]+", 0},
            {"regex", "^first\\nvalue: [0-9]+\\nlast\\n$", 0},
            {"regex", "^value: [0-9]+$", 1},
            {"regex", "[", 1},
            {"contains", "value: 42\nlast", 0},
            {"contains", "value: 43", 1}
          ] do
        {:ok, workflow} =
          Actions.generate_workflow([
            Map.merge(base, %{output_comparison: mode, expected: expected})
          ])

        {output, status} =
          workflow |> workflow_script!() |> run_script(runner_temp, repository, timeout_env)

        assert status == expected_status
        if expected == "[", do: assert(output =~ "FAIL: invalid regular expression.")
        if mode == "regex", do: refute(output =~ "Output difference:")
        assert workflow =~ "10s node --input-type=commonjs"
      end

      assert {:error, :invalid_autograding_tests} =
               Actions.generate_workflow([
                 Map.merge(base, %{
                   output_comparison: "regex",
                   expected: String.duplicate("a", 4097)
                 })
               ])
    end)
  end

  test "a failing IO program cannot pass with matching output and comparison errors restore commands" do
    with_runtime(fn runner_temp, repository, timeout_env ->
      spec =
        Map.merge(command_test("printf hello; exit 7"), %{
          type: "io",
          expected: "hello",
          output_comparison: "regex"
        })

      {:ok, workflow} = Actions.generate_workflow([spec])

      {output, 1} =
        workflow |> workflow_script!() |> run_script(runner_temp, repository, timeout_env)

      assert output =~ "FAIL: test command exited with code 7."
      refute output =~ "PASS:"
      assert output =~ "::stop-commands::"
      assert Regex.match?(~r/\n::[a-f0-9]{64}::\n/, output)
    end)
  end

  test "a successful program cannot pass comparison after exceeding the capture limit" do
    with_runtime(fn runner_temp, repository, timeout_env ->
      spec =
        Map.merge(command_test(~S|node -e 'process.stdout.write("x".repeat(8388609))'|), %{
          type: "io",
          expected: "x+",
          output_comparison: "regex"
        })

      {:ok, workflow} = Actions.generate_workflow([spec])
      # Exercise the size check independently of OS-specific SIGXFSZ behavior.
      script =
        workflow |> workflow_script!() |> String.replace("ulimit -f 8193", "ulimit -f unlimited")

      {output, 1} = run_script(script, runner_temp, repository, timeout_env)
      assert output =~ "FAIL: program output exceeded the 8 MiB file limit."
      refute output =~ "PASS:"
    end)
  end

  test "file checks report a clear result" do
    with_runtime(fn runner_temp, repository, timeout_env ->
      File.mkdir_p!(Path.join(repository, "project files"))
      File.write!(Path.join(repository, "project files/main.c"), "int main(void) {}")

      test = %{
        id: 1,
        name: "Main source",
        type: "file",
        path: "project files/main.c",
        points: 1,
        timeout_seconds: 60
      }

      {:ok, workflow} = Actions.generate_workflow([test])

      {output, status} =
        workflow |> workflow_script!() |> run_script(runner_temp, repository, timeout_env)

      assert status == 0
      assert workflow =~ "Check required file: project files/main.c"
      assert output =~ "Required file: project files/main.c"
      assert output =~ "PASS: required file exists."
    end)
  end

  test "file checks reject absolute and traversal paths" do
    assert {:error, :invalid_autograding_tests} =
             Actions.generate_workflow([
               %{
                 id: 1,
                 name: "File",
                 type: "file",
                 path: "../secret",
                 points: 1,
                 timeout_seconds: 60
               }
             ])

    assert {:error, :invalid_autograding_tests} =
             Actions.generate_workflow([
               %{
                 id: 1,
                 name: "File",
                 type: "file",
                 path: "/etc/passwd",
                 points: 1,
                 timeout_seconds: 60
               }
             ])
  end

  test "test job results require exactly one expected job per configured test" do
    tests = [
      %{id: 1, name: "Compile", points: 3},
      %{id: 2, name: "Examples", points: 2}
    ]

    jobs = [
      %{"name" => "GradePush test [gp-test-1] Compile", "conclusion" => "success"},
      %{"name" => "GradePush test [gp-test-2] Examples", "conclusion" => "failure"}
    ]

    assert {:ok, %{score: 3, max_score: 5, tests: results}} = Actions.job_results(jobs, tests)
    assert Enum.map(results, & &1.status) |> Enum.sort() == ["failure", "success"]

    assert {:error, :incomplete_workflow_results} =
             Actions.job_results([hd(jobs), hd(jobs)], tests)
  end

  test "configured identifiers cannot collide after conversion to workflow job names" do
    tests = [
      %{id: 1, name: "One", type: "file", path: "one", points: 1, timeout_seconds: 60},
      %{id: "1", name: "Another one", type: "file", path: "two", points: 1, timeout_seconds: 60}
    ]

    assert {:error, :invalid_autograding_tests} = Actions.generate_workflow(tests)
  end

  defp command_test(command) do
    %{
      id: 1,
      name: "Runtime command",
      type: "command",
      command: command,
      points: 1,
      timeout_seconds: 60
    }
  end

  defp with_runtime(fun) do
    root = Path.join(System.tmp_dir!(), "gradepush-actions-#{System.unique_integer([:positive])}")
    runner_temp = Path.join(root, "runner")
    repository = Path.join(root, "repository")
    bin = Path.join(root, "bin")
    File.mkdir_p!(runner_temp)
    File.mkdir_p!(repository)

    timeout_env =
      if System.find_executable("timeout") do
        []
      else
        File.mkdir_p!(bin)
        shim = Path.join(bin, "timeout")

        File.write!(
          shim,
          """
          #!/bin/sh
          if [ "${GRADE_PUSH_FAKE_TIMEOUT:-}" = "1" ]; then exit 124; fi
          shift 3
          exec "$@"
          """
        )

        File.chmod!(shim, 0o755)
        [{"PATH", bin <> ":" <> System.get_env("PATH", "")}]
      end

    try do
      fun.(runner_temp, repository, timeout_env)
    after
      File.rm_rf!(root)
    end
  end

  defp run_script(script, runner_temp, repository, timeout_env) do
    System.cmd("bash", ["-c", script],
      cd: repository,
      env: [{"RUNNER_TEMP", runner_temp} | timeout_env],
      stderr_to_stdout: true
    )
  end

  defp workflow_script!(workflow) do
    workflow |> workflow_scripts!() |> hd()
  end

  defp workflow_scripts!(workflow) do
    workflow
    |> String.split("        run: |\n")
    |> tl()
    |> Enum.map(fn block ->
      block
      |> String.split("\n")
      |> Enum.take_while(&(&1 == "" or String.starts_with?(&1, "          ")))
      |> Enum.map_join("\n", &String.replace_prefix(&1, "          ", ""))
    end)
  end
end
