defmodule GradePush.Installation.GitHubApp do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "github_apps" do
    field :singleton_key, :boolean, default: true
    field :app_id, :integer
    field :client_id, :string
    field :client_secret_encrypted, :binary
    field :private_key_encrypted, :binary
    field :webhook_secret_encrypted, :binary
    field :slug, :string
    field :html_url, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(app, attrs) do
    app
    |> cast(attrs, [
      :app_id,
      :client_id,
      :client_secret_encrypted,
      :private_key_encrypted,
      :webhook_secret_encrypted,
      :slug,
      :html_url
    ])
    |> validate_required([
      :app_id,
      :client_id,
      :client_secret_encrypted,
      :private_key_encrypted,
      :webhook_secret_encrypted,
      :slug,
      :html_url
    ])
    |> unique_constraint(:singleton_key)
  end
end
