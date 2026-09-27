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
    workflow
    |> String.split("        run: |\n", parts: 2)
    |> List.last()
    |> String.split("\n")
    |> Enum.take_while(&String.starts_with?(&1, "          "))
    |> Enum.map_join("\n", &String.replace_prefix(&1, "          ", ""))
  end
end
