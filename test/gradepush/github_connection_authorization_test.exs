defmodule GradePush.GitHubConnectionAuthorizationTest do
  use GradePush.DataCase, async: false

  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures

  alias GradePush.{Assignments, Classrooms, Crypto, Repo}
  alias GradePush.Classrooms.GitHubConnection
  alias GradePush.GitHub.Fake
  alias GradePush.Installation.GitHubApp

  setup do
    previous = Application.get_env(:gradepush, GradePush.GitHub, [])
    Application.put_env(:gradepush, GradePush.GitHub, Keyword.put(previous, :adapter, Fake))
    Fake.reset!()

    on_exit(fn ->
      Application.put_env(:gradepush, GradePush.GitHub, previous)
      Fake.reset!()
    end)

    :ok
  end

  test "a classroom colleague cannot use a private organization connection or its templates" do
    %{user: owner} = bootstrap_fixture()
    insert_app()
    classroom = classroom_fixture(owner)

    connection = Repo.get!(GitHubConnection, classroom.github_connection_id)

    connection
    |> GitHubConnection.changeset(%{
      github_organization_id: 789,
      login: "gradepush-test",
      installation_id: 123
    })
    |> Repo.update!()

    colleague = user_fixture(%{login: "colleague"})
    teacher_membership_fixture(colleague)
    assert {:ok, _} = Classrooms.add_teacher(owner, classroom.id, colleague.id)

    assignment_attrs = %{
      title: "Template lab",
      instructions: "Start from the approved template.",
      template_repository: "gradepush-test/starter",
      repository_visibility: "public"
    }

    assert {:ok, assignment} =
             Assignments.create_assignment(owner, classroom.id, assignment_attrs)

    assert {:error, :github_connection_unavailable} =
             Assignments.create_assignment(colleague, classroom.id, assignment_attrs)

    assert {:error, :github_connection_unavailable} =
             Assignments.update_assignment(colleague, assignment.id, %{
               template_repository: "gradepush-test/starter",
               repository_visibility: "public"
             })

    assert {:error, :template_not_available} =
             Assignments.create_assignment(owner, classroom.id, %{
               title: "Unlisted template",
               template_repository: "gradepush-test/not-a-template"
             })
  end

  defp insert_app do
    {:ok, client_secret} = Crypto.encrypt("test-client-secret", "github_app.client_secret")
    {:ok, private_key} = Crypto.encrypt("test-private-key", "github_app.private_key")
    {:ok, webhook_secret} = Crypto.encrypt("test-webhook-secret", "github_app.webhook_secret")

    %GitHubApp{}
    |> GitHubApp.changeset(%{
      app_id: 456,
      client_id: "test-client-id",
      client_secret_encrypted: client_secret,
      private_key_encrypted: private_key,
      webhook_secret_encrypted: webhook_secret,
      slug: "gradepush-test",
      html_url: "https://github.com/apps/gradepush-test"
    })
    |> Repo.insert!()
  end
end
