defmodule GradePush.Submissions.Push do
  use Ecto.Schema
  import Ecto.Changeset

  alias GradePush.Assignments.{Repository, Subject}

  schema "submission_pushes" do
    field :commit_sha, :string
    field :branch, :string
    field :observed_at, :utc_datetime_usec
    field :delivery_id, :string

    belongs_to :subject, Subject
    belongs_to :repository, Repository

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(push, attrs) do
    push
    |> cast(attrs, [:subject_id, :repository_id, :commit_sha, :branch, :observed_at, :delivery_id])
    |> validate_required([:subject_id, :repository_id, :commit_sha, :observed_at, :delivery_id])
    |> validate_format(:commit_sha, ~r/\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/i)
    |> validate_length(:delivery_id, min: 1, max: 100)
    |> validate_length(:branch, max: 255)
    |> unique_constraint(:delivery_id)
    |> foreign_key_constraint(:subject_id)
    |> foreign_key_constraint(:repository_id)
  end
end
