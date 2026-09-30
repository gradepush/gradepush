defmodule GradePush.Repo.Migrations.TrackWorkflowAttempts do
  use Ecto.Migration

  def up do
    alter table(:autograding_results) do
      add :run_attempt, :integer, null: false, default: 1
    end

    create constraint(:autograding_results, :autograding_results_run_attempt_positive,
             check: "run_attempt > 0"
           )

    create unique_index(:autograding_results, [:repository_id, :run_id, :run_attempt])
    drop unique_index(:autograding_results, [:repository_id, :run_id])
  end

  def down do
    # Retain every assessed attempt; rolling back requires restoring a pre-upgrade backup.
    raise "Restore the pre-upgrade database backup to roll back workflow attempt tracking"
  end
end
