defmodule GradePush.Repo.Migrations.AddTeamAccessManagement do
  use Ecto.Migration

  def change do
    drop unique_index(:assignment_teams, [:assignment_id, :name])

    create unique_index(:assignment_teams, [:assignment_id, :name], where: "archived_at IS NULL")

    alter table(:assignment_repositories) do
      add :access_sync_state, :text, null: false, default: "synced"
      add :access_version, :bigint, null: false, default: 0
    end

    create constraint(:assignment_repositories, :valid_access_sync_state,
             check: "access_sync_state IN ('pending', 'synced', 'failed')"
           )
  end
end
