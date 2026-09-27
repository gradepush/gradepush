defmodule GradePush.Submissions.GradeTest do
  use Ecto.Schema
  import Ecto.Changeset

  alias GradePush.Assignments.AssignmentTest
  alias GradePush.Submissions.Grade

  schema "autograding_test_results" do
    field :name, :string
    field :status, :string
    field :points_awarded, :decimal
    field :max_points, :decimal

    belongs_to :result, Grade
    belongs_to :assignment_test, AssignmentTest

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(test, attrs) do
    test
    |> cast(attrs, [:name, :status, :points_awarded, :max_points, :assignment_test_id])
    |> validate_required([:name, :status, :points_awarded, :max_points, :assignment_test_id])
    |> validate_length(:name, min: 1, max: 120)
    |> validate_inclusion(:status, ~w(success failure cancelled skipped))
    |> validate_number(:points_awarded, greater_than_or_equal_to: 0)
    |> validate_number(:max_points, greater_than_or_equal_to: 0)
    |> check_constraint(:points_awarded, name: :autograding_test_results_score_check)
    |> foreign_key_constraint(:assignment_test_id)
  end
end
