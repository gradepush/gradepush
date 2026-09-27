defmodule GradePush.Installation.GitHubUserCredentials do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias GradePush.Accounts.User

  schema "github_user_credentials" do
    field :access_token_encrypted, :binary
    field :refresh_token_encrypted, :binary
    field :expires_at, :utc_datetime_usec
    field :refresh_token_expires_at, :utc_datetime_usec
    field :scopes, {:array, :string}, default: []
    belongs_to :user, User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(credentials, attrs) do
    credentials
    |> cast(attrs, [
      :user_id,
      :access_token_encrypted,
      :refresh_token_encrypted,
      :expires_at,
      :refresh_token_expires_at,
      :scopes
    ])
    |> validate_required([:user_id, :access_token_encrypted, :scopes])
    |> unique_constraint(:user_id)
  end
end
