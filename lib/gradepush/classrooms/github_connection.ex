defmodule GradePush.Classrooms.GitHubConnection do
  use Ecto.Schema
  import Ecto.Changeset

  alias GradePush.Accounts.User

  schema "github_organization_connections" do
    field :github_organization_id, :integer
    field :login, :string
    field :installation_id, :integer
    field :status, :string, default: "active"

    belongs_to :connected_by, User

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [
      :github_organization_id,
      :login,
      :installation_id,
      :status,
      :connected_by_id
    ])
    |> validate_required([
      :github_organization_id,
      :login,
      :installation_id,
      :status,
      :connected_by_id
    ])
    |> validate_inclusion(:status, ~w(active revoked suspended))
    |> validate_length(:login, min: 1, max: 100)
    |> unique_constraint(:github_organization_id)
    |> foreign_key_constraint(:connected_by_id)
  end
end
