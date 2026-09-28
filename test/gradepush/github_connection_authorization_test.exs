defmodule GradePush.GitHubConnectionAuthorizationTest do
  use GradePush.DataCase, async: false

  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures

  alias GradePush.{Assignments, Classrooms, Crypto, Installation, Repo}
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

  test "discovery excludes personal accounts and other apps while supporting multiple organizations" do
    %{user: teacher} = configured_gradepush_fixture()
    {:ok, [installation]} = Fake.list_installations(%{})
    personal = installation |> Map.put("id", 121) |> put_in(["account", "type"], "User")
    another_app = installation |> Map.put("id", 122) |> Map.put("app_id", 999)

    second =
      installation
      |> Map.put("id", 124)
      |> put_in(["account", "id"], 790)
      |> put_in(["account", "login"], "another-school")

    Fake.set_installations([personal, another_app, installation, second])

    assert {:ok, organizations} = Installation.list_user_organizations(teacher)
    assert Enum.map(organizations, & &1.login) == ["gradepush-test", "another-school"]
    assert {:ok, _} = Classrooms.connect_github_organization(teacher, 123)
    Fake.set_organization_membership("another-school", %{"state" => "active", "role" => "admin"})
    assert {:ok, _} = Classrooms.connect_github_organization(teacher, 124)
    assert {:ok, connections} = Classrooms.list_github_connections(teacher)
    assert length(connections) == 2

    Fake.set_installations([Map.put(personal, "id", 123)])

    assert {:error, :installation_not_authorized} =
             Classrooms.connect_github_organization(teacher, 123)
  end

  test "connection checks require access and reject suspended, revoked or mismatched installations" do
    %{user: owner} = configured_gradepush_fixture()
    {:ok, connection} = Classrooms.connect_github_organization(owner, 123)
    colleague = user_fixture()
    teacher_membership_fixture(colleague)

    assert :ok = Classrooms.check_github_connection(owner, connection.id)
    assert {:error, :not_found} = Classrooms.check_github_connection(colleague, connection.id)

    assert {:error, :unauthorized} =
             Classrooms.check_github_connection(student_fixture(), connection.id)

    authorize_github(colleague)
    assert {:ok, reused} = Classrooms.connect_github_organization(colleague, 123)
    assert reused.id == connection.id
    assert {:ok, same} = Classrooms.connect_github_organization(colleague, 123)
    assert same.id == connection.id
    assert :ok = Classrooms.check_github_connection(colleague, connection.id)
    assert {:ok, [_]} = Classrooms.list_github_connections(colleague)
    assert Repo.aggregate(GitHubConnection, :count) == 1

    {:ok, [installation]} = Fake.list_installations(%{})

    for invalid <- [
          Map.put(installation, "suspended_at", "2026-09-27T10:00:00Z"),
          Map.put(installation, "app_id", 999),
          put_in(installation, ["account", "id"], 999),
          put_in(installation, ["permissions", "administration"], "read")
        ] do
      Fake.set_installations([invalid])

      assert {:error, :connection_unavailable} =
               Classrooms.check_github_connection(owner, connection.id)
    end

    Fake.set_installations([])
    assert {:error, :not_found} = Classrooms.check_github_connection(owner, connection.id)
  end

  test "knowing a connected installation does not grant access without personal GitHub authorization" do
    %{user: owner} = configured_gradepush_fixture()
    {:ok, connection} = Classrooms.connect_github_organization(owner, 123)
    colleague = user_fixture()
    teacher_membership_fixture(colleague)

    assert {:error, :github_reauthorization_required} =
             Classrooms.connect_github_organization(colleague, 123)

    authorize_github(colleague)
    Fake.set_organization_membership("gradepush-test", %{"state" => "active", "role" => "member"})

    assert {:error, :organization_owner_required} =
             Classrooms.connect_github_organization(colleague, 123)

    assert {:error, :not_found} = Classrooms.get_github_connection(colleague, connection.id)
    assert {:ok, []} = Classrooms.list_github_connections(colleague)
  end

  defp authorize_github(user) do
    {:ok, token} = Crypto.encrypt("test-colleague-token", "github_user.#{user.id}.access_token")

    Repo.insert!(%GradePush.Installation.GitHubUserCredentials{
      user_id: user.id,
      access_token_encrypted: token,
      scopes: []
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
