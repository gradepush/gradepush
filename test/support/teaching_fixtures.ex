defmodule GradePush.TeachingFixtures do
  @moduledoc false

  alias GradePush.Accounts
  alias GradePush.Accounts.User
  alias GradePush.Assignments
  alias GradePush.Classrooms
  alias GradePush.Classrooms.GitHubConnection
  alias GradePush.Crypto
  alias GradePush.Installation.{GitHubApp, GitHubUserCredentials}
  alias GradePush.Repo

  def student_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)

    github_id =
      Map.get(attrs, :github_id, 1_000_000 + System.unique_integer([:positive, :monotonic]))

    {:ok, student} =
      Accounts.upsert_github_user(
        Map.merge(%{github_id: github_id, login: "student-#{github_id}"}, attrs)
      )

    {:ok, _membership} =
      Accounts.enroll_student(student, %{
        name: Map.get(attrs, :student_name, "Test Student"),
        student_id: Map.get(attrs, :student_id, "student-#{github_id}")
      })

    Accounts.get_user(student.id)
  end

  def classroom_fixture(%User{} = teacher, attrs \\ %{}) do
    attrs = Map.new(attrs)
    connection = connection_for(teacher)

    term_attrs =
      if Map.has_key?(attrs, :semester) or Map.has_key?(attrs, :academic_year),
        do: Map.take(attrs, [:semester, :academic_year]),
        else: %{semester: :fall, academic_year: "2026"}

    {:ok, classroom} =
      Classrooms.create_classroom(
        teacher,
        Map.merge(
          %{
            title: Map.get(attrs, :title, "Programming #{System.unique_integer([:positive])}"),
            code: Map.get(attrs, :code, "CS-#{System.unique_integer([:positive])}"),
            description: Map.get(attrs, :description, "Test classroom"),
            github_connection_id: connection.id
          },
          term_attrs
        )
      )

    classroom
  end

  def assignment_fixture(%User{} = teacher, classroom, attrs \\ %{}) do
    attrs = Map.new(attrs)

    {:ok, assignment} =
      Assignments.create_assignment(teacher, classroom.id, %{
        title: Map.get(attrs, :title, "Assignment #{System.unique_integer([:positive])}"),
        instructions: Map.get(attrs, :instructions, "Complete the exercises."),
        kind: Map.get(attrs, :kind, "individual"),
        team_mode: Map.get(attrs, :team_mode, "students"),
        team_size: Map.get(attrs, :team_size, 2),
        repository_visibility: Map.get(attrs, :repository_visibility, "private"),
        autograding_enabled: Map.get(attrs, :autograding_enabled, false),
        tests: Map.get(attrs, :tests, [])
      })

    assignment
  end

  defp connection_for(teacher) do
    authorize_github_fixture(teacher)

    case Repo.get_by(GitHubConnection, connected_by_id: teacher.id) do
      %GitHubConnection{status: "active"} = connection ->
        connection

      _ ->
        {:ok, connection} = Classrooms.connect_github_organization(teacher, 123)
        connection
    end
  end

  def authorize_github_fixture(teacher) do
    unless Repo.exists?(GitHubApp) do
      {:ok, secret} = Crypto.encrypt("test-client-secret", "github_app.client_secret")
      {:ok, key} = Crypto.encrypt("test-private-key", "github_app.private_key")
      {:ok, webhook} = Crypto.encrypt("test-webhook-secret", "github_app.webhook_secret")

      Repo.insert!(%GitHubApp{
        app_id: 456,
        client_id: "test-client-id",
        client_secret_encrypted: secret,
        private_key_encrypted: key,
        webhook_secret_encrypted: webhook,
        slug: "gradepush-test",
        html_url: "https://github.com/apps/gradepush-test"
      })
    end

    unless Repo.get_by(GitHubUserCredentials, user_id: teacher.id) do
      {:ok, token} = Crypto.encrypt("test-user-token", "github_user.#{teacher.id}.access_token")

      Repo.insert!(%GitHubUserCredentials{
        user_id: teacher.id,
        access_token_encrypted: token,
        scopes: []
      })
    end

    :ok
  end
end
