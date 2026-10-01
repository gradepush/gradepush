defmodule GradePush.Assignments.Repository do
  use Ecto.Schema
  import Ecto.Changeset

  alias GradePush.Assignments.Subject

  schema "assignment_repositories" do
    field :github_repository_id, :integer
    field :owner_login, :string
    field :name, :string
    field :full_name, :string
    field :html_url, :string
    field :workflow_id, :integer
    field :workflow_path, :string
    field :workflow_file_sha, :string
    field :state, :string, default: "pending"
    field :last_error, :string
    field :access_sync_state, :string, default: "synced"
    field :access_version, :integer, default: 0

    belongs_to :subject, Subject

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(repository, attrs) do
    repository
    |> cast(attrs, [
      :github_repository_id,
      :owner_login,
      :name,
      :full_name,
      :html_url,
      :workflow_id,
      :workflow_path,
      :workflow_file_sha,
      :state,
      :last_error,
      :subject_id
    ])
    |> validate_required([:subject_id, :state])
    |> validate_inclusion(:state, ~w(pending ready failed))
    |> validate_length(:last_error, max: 1_000)
    |> validate_length(:workflow_path, max: 255)
    |> validate_length(:workflow_file_sha, max: 64)
    |> foreign_key_constraint(:subject_id)
    |> unique_constraint(:subject_id)
    |> unique_constraint(:github_repository_id)
  end
end
