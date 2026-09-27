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
    refute workflow =~ command
    refute workflow =~ "GITHUB_TOKEN"
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
end
