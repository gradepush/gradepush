defmodule GradePush.Classrooms.GitHubConnectionTeacher do
  @primary_key false
  use Ecto.Schema

  alias GradePush.Accounts.User
  alias GradePush.Classrooms.GitHubConnection

  schema "github_connection_teachers" do
    belongs_to :connection, GitHubConnection
    belongs_to :user, User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
