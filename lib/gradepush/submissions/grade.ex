defmodule GradePush.Submissions.Grade do
  use Ecto.Schema
  import Ecto.Changeset

  alias GradePush.Assignments.{Repository, Subject}
  alias GradePush.Submissions.GradeTest

  schema "autograding_results" do
    field :commit_sha, :string
    field :run_id, :integer
    field :run_attempt, :integer, default: 1
    field :status, :string
    field :score, :decimal
    field :max_score, :decimal
    field :html_url, :string
    field :reason, :string

    belongs_to :subject, Subject
    belongs_to :repository, Repository
    has_many :tests, GradeTest, foreign_key: :result_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(grade, attrs) do
    grade
    |> cast(attrs, [
      :subject_id,
      :repository_id,
      :commit_sha,
      :run_id,
      :run_attempt,
      :status,
      :score,
      :max_score,
      :html_url,
      :reason
    ])
    |> validate_required([
      :subject_id,
      :repository_id,
      :commit_sha,
      :run_id,
      :run_attempt,
      :status,
      :score,
      :max_score
    ])
    |> validate_format(:commit_sha, ~r/\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/i)
    |> validate_inclusion(
      :status,
      ~w(success failure cancelled timed_out queued in_progress untrusted)
    )
    |> validate_inclusion(:reason, ~w(workflow_modified), allow_nil: true)
    |> validate_number(:score, greater_than_or_equal_to: 0)
    |> validate_number(:run_attempt, greater_than: 0)
    |> validate_number(:max_score, greater_than_or_equal_to: 0)
    |> validate_length(:html_url, max: 2_048)
    |> check_constraint(:score, name: :autograding_results_score_check)
    |> unique_constraint([:repository_id, :run_id, :run_attempt])
    |> foreign_key_constraint(:subject_id)
    |> foreign_key_constraint(:repository_id)
  end
end
