defmodule GradePush.TeachingFixtures do
  @moduledoc false

  alias GradePush.Accounts
  alias GradePush.Accounts.User
  alias GradePush.Assignments
  alias GradePush.Classrooms
  alias GradePush.Classrooms.GitHubConnection
  alias GradePush.Repo

  def student_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    github_id = Map.get(attrs, :github_id, System.unique_integer([:positive, :monotonic]))

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
      cond do
        Map.has_key?(attrs, :semester) or Map.has_key?(attrs, :academic_year) ->
          Map.take(attrs, [:semester, :academic_year])

        Map.has_key?(attrs, :session) ->
          %{}

        true ->
          %{semester: "fall", academic_year: 2026}
      end

    {:ok, classroom} =
      Classrooms.create_classroom(
        teacher,
        Map.merge(
          %{
            title: Map.get(attrs, :title, "Programming #{System.unique_integer([:positive])}"),
            code: Map.get(attrs, :code, "CS-#{System.unique_integer([:positive])}"),
            description: Map.get(attrs, :description, "Test classroom"),
            session: Map.get(attrs, :session, ""),
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
    case Repo.get_by(GitHubConnection, connected_by_id: teacher.id) do
      %GitHubConnection{status: "active"} = connection ->
        connection

      _ ->
        unique = System.unique_integer([:positive, :monotonic])

        %GitHubConnection{}
        |> GitHubConnection.changeset(%{
          github_organization_id: unique,
          login: "gradepush-test-#{unique}",
          installation_id: unique,
          sharing_scope: "private",
          status: "active",
          connected_by_id: teacher.id
        })
        |> Repo.insert!()
    end
  end
end
