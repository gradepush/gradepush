defmodule GradePush.AssignmentGitHubAuthorizationTest do
  use GradePush.DataCase, async: false

  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures

  alias GradePush.{Assignments, Classrooms, Repo}
  alias GradePush.Assignments.Assignment
  alias GradePush.GitHub.Fake

  defmodule RecordingAdapter do
    @behaviour GradePush.GitHub

    for {name, arity} <- GradePush.GitHub.behaviour_info(:callbacks) do
      args = Macro.generate_arguments(arity, __MODULE__)

      def unquote(name)(unquote_splicing(args)) do
        calls = Process.get(:assignment_github_calls, %{})
        Process.put(:assignment_github_calls, Map.update(calls, unquote(name), 1, &(&1 + 1)))
        apply(Fake, unquote(name), [unquote_splicing(args)])
      end
    end
  end

  setup do
    previous = Application.get_env(:gradepush, GradePush.GitHub, [])

    Application.put_env(
      :gradepush,
      GradePush.GitHub,
      Keyword.put(previous, :adapter, RecordingAdapter)
    )

    Fake.reset!()

    on_exit(fn ->
      Application.put_env(:gradepush, GradePush.GitHub, previous)
      Fake.reset!()
    end)

    %{user: teacher} = configured_gradepush_fixture()
    %{teacher: teacher, classroom: classroom_fixture(teacher)}
  end

  test "each save verifies GitHub access once, with and without a template", context do
    %{teacher: teacher, classroom: classroom} = context
    Process.put(:assignment_github_calls, %{})

    assert {:ok, assignment} =
             Assignments.create_assignment(teacher, classroom.id, %{
               title: "Template lab",
               template_repository: "gradepush-test/starter"
             })

    assert_single_verification(true)
    Process.put(:assignment_github_calls, %{})

    assert {:ok, _} =
             Assignments.update_assignment(teacher, assignment.id, %{title: "Updated lab"})

    assert_single_verification(true)
    Process.put(:assignment_github_calls, %{})

    assert {:ok, _} =
             Assignments.update_assignment(teacher, assignment.id, %{template_repository: ""})

    assert_single_verification(false)
    Process.put(:assignment_github_calls, %{})

    assert {:ok, _} =
             Assignments.create_assignment(teacher, classroom.id, %{title: "No starter"})

    assert_single_verification(false)
  end

  test "a successful save never caches authorization for the next operation", context do
    %{teacher: teacher, classroom: classroom} = context
    assignment = assignment_fixture(teacher, classroom)
    Fake.set_organization_membership("gradepush-test", %{"state" => "active", "role" => "member"})

    for template <- [nil, "gradepush-test/starter"] do
      assert {:error, :github_connection_unavailable} =
               Assignments.update_assignment(teacher, assignment.id, %{
                 title: "Denied update",
                 template_repository: template
               })

      assert {:error, :github_connection_unavailable} =
               Assignments.create_assignment(teacher, classroom.id, %{
                 title: "Denied creation",
                 template_repository: template
               })
    end

    assert Repo.get!(Assignment, assignment.id).title == assignment.title
    assert Repo.aggregate(Assignment, :count) == 1
    assert {:ok, []} = Classrooms.list_github_connections(teacher)
  end

  test "transient verification errors deny saving and leave the grant usable", context do
    %{teacher: teacher, classroom: classroom} = context
    assignment = assignment_fixture(teacher, classroom)
    Fake.fail_next(:get_user_organization_membership, {:github_unavailable, 503})

    assert {:error, :github_connection_unavailable} =
             Assignments.update_assignment(teacher, assignment.id, %{title: "Denied update"})

    assert Repo.get!(Assignment, assignment.id).title == assignment.title

    assert {:ok, _} =
             Assignments.update_assignment(teacher, assignment.id, %{title: "Recovered update"})
  end

  defp assert_single_verification(template?) do
    expected = %{
      get_user_installation: 1,
      get_installation: 1,
      get_user_organization_membership: 1
    }

    expected =
      if template?,
        do: Map.merge(expected, %{installation_token: 1, list_template_repositories: 1}),
        else: expected

    assert Process.get(:assignment_github_calls) == expected
  end
end
