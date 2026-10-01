defmodule GradePush.Repo.Migrations.CreateTeaching do
  use Ecto.Migration

  def change do
    create table(:github_organization_connections) do
      add :github_organization_id, :bigint, null: false
      add :login, :string, null: false
      add :installation_id, :bigint, null: false
      add :status, :string, null: false, default: "active"
      add :connected_by_id, references(:users, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:github_organization_connections, [:github_organization_id])
    create unique_index(:github_organization_connections, [:installation_id])

    create constraint(:github_organization_connections, :github_connection_status_check,
             check: "status IN ('active', 'revoked', 'suspended')"
           )

    create table(:github_connection_teachers, primary_key: false) do
      add :connection_id,
          references(:github_organization_connections, on_delete: :delete_all),
          null: false,
          primary_key: true

      add :user_id, references(:users, on_delete: :delete_all), null: false, primary_key: true
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:github_connection_teachers, [:user_id])

    create table(:classrooms) do
      add :slug, :string, null: false
      add :title, :string, null: false
      add :code, :string, null: false, default: ""
      add :description, :text, null: false, default: ""
      add :semester, :integer
      add :academic_year, :text
      add :archived_at, :utc_datetime_usec
      add :created_by_id, references(:users, on_delete: :restrict), null: false

      add :github_connection_id,
          references(:github_organization_connections, on_delete: :restrict),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:classrooms, [:slug])
    create index(:classrooms, [:created_by_id])
    create index(:classrooms, [:github_connection_id])

    create constraint(:classrooms, :classroom_term_check,
             check:
               "(semester IS NULL AND academic_year IS NULL) OR (semester IS NOT NULL AND academic_year IS NOT NULL AND semester IN (1, 2, 3) AND char_length(academic_year) BETWEEN 1 AND 20 AND academic_year ~ '[^[:space:]]')"
           )

    create table(:classroom_teachers, primary_key: false) do
      add :classroom_id, references(:classrooms, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :user_id, references(:users, on_delete: :restrict), null: false, primary_key: true
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:classroom_teachers, [:user_id])

    create table(:classroom_students) do
      add :classroom_id, references(:classrooms, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :restrict), null: false
      add :joined_at, :utc_datetime_usec, null: false
      add :removed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:classroom_students, [:classroom_id, :user_id])
    create index(:classroom_students, [:classroom_id, :removed_at])
    create index(:classroom_students, [:user_id, :removed_at])

    create table(:classroom_invitations) do
      add :classroom_id, references(:classrooms, on_delete: :delete_all), null: false
      add :created_by_id, references(:users, on_delete: :restrict), null: false
      add :token_hash, :binary, null: false
      add :token_encrypted, :binary, null: false
      add :expires_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:classroom_invitations, [:token_hash])
    create index(:classroom_invitations, [:classroom_id, :revoked_at])
    create unique_index(:classroom_invitations, [:classroom_id], where: "revoked_at IS NULL")

    create table(:assignments) do
      add :classroom_id, references(:classrooms, on_delete: :delete_all), null: false
      add :slug, :string, null: false
      add :title, :string, null: false
      add :instructions, :text, null: false, default: ""
      add :kind, :string, null: false, default: "individual"
      add :team_mode, :string, null: false, default: "students"
      add :team_size, :integer, null: false, default: 2
      add :deadline_at, :utc_datetime_usec
      add :cutoff_enabled, :boolean, null: false, default: false
      add :template_repository, :string

      add :repository_name_pattern, :string,
        null: false,
        default: "{classroom}-{assignment}-{identifier}"

      add :repository_visibility, :string, null: false, default: "private"
      add :autograding_enabled, :boolean, null: false, default: false
      add :published_at, :utc_datetime_usec
      add :archived_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:assignments, [:classroom_id, :slug])
    create index(:assignments, [:classroom_id, :archived_at])

    create constraint(:assignments, :assignments_kind_check,
             check: "kind IN ('individual', 'team')"
           )

    create constraint(:assignments, :assignments_team_mode_check,
             check: "team_mode IN ('students', 'teacher')"
           )

    create constraint(:assignments, :assignments_team_size_check,
             check: "team_size BETWEEN 2 AND 20"
           )

    create constraint(:assignments, :assignments_visibility_check,
             check: "repository_visibility IN ('private', 'public')"
           )

    create constraint(:assignments, :assignments_cutoff_deadline_check,
             check: "NOT cutoff_enabled OR deadline_at IS NOT NULL"
           )

    create table(:assignment_tests) do
      add :assignment_id, references(:assignments, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text, null: false, default: ""
      add :type, :string, null: false
      add :points, :integer, null: false
      add :timeout_seconds, :integer, null: false, default: 300
      add :output_comparison, :text, null: false, default: "trim_trailing"
      add :runtime, :text, null: false, default: "system"
      add :setup_command, :text, null: false, default: ""
      add :command, :text
      add :path, :string
      add :input, :text
      add :expected, :text
      timestamps(type: :utc_datetime_usec)
    end

    create index(:assignment_tests, [:assignment_id])

    create constraint(:assignment_tests, :assignment_tests_type_check,
             check: "type IN ('command', 'file', 'io')"
           )

    create constraint(:assignment_tests, :assignment_tests_points_check,
             check: "points BETWEEN 1 AND 1000"
           )

    create constraint(:assignment_tests, :assignment_tests_timeout_check,
             check: "timeout_seconds BETWEEN 30 AND 1200"
           )

    create constraint(:assignment_tests, :assignment_tests_comparison_check,
             check: "output_comparison IN ('exact', 'trim_trailing', 'contains', 'regex')"
           )

    create constraint(:assignment_tests, :assignment_tests_runtime_check,
             check:
               "runtime IN ('system', 'python-3.14.7', 'node-24.21.0', 'php-8.5.11', 'java-25', 'c-cpp-14')"
           )

    create constraint(:assignment_tests, :assignment_tests_command_check,
             check: "type != 'command' OR command IS NOT NULL AND length(command) > 0"
           )

    create constraint(:assignment_tests, :assignment_tests_file_check,
             check: "type != 'file' OR path IS NOT NULL AND length(path) > 0"
           )

    create constraint(:assignment_tests, :assignment_tests_io_check,
             check: "type != 'io' OR command IS NOT NULL AND expected IS NOT NULL"
           )

    create table(:assignment_teams) do
      add :assignment_id, references(:assignments, on_delete: :delete_all), null: false
      add :created_by_id, references(:users, on_delete: :restrict), null: false
      add :name, :string, null: false
      add :join_code, :string
      add :archived_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:assignment_teams, [:assignment_id, :name])
    create unique_index(:assignment_teams, [:join_code])
    create index(:assignment_teams, [:assignment_id, :archived_at])

    create table(:assignment_team_members) do
      add :team_id, references(:assignment_teams, on_delete: :delete_all), null: false
      add :assignment_id, references(:assignments, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :restrict), null: false
      add :left_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:assignment_team_members, [:team_id, :user_id])
    create index(:assignment_team_members, [:user_id, :left_at])

    create unique_index(:assignment_team_members, [:assignment_id, :user_id],
             where: "left_at IS NULL"
           )

    create table(:assignment_subjects) do
      add :assignment_id, references(:assignments, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :user_id, references(:users, on_delete: :restrict)
      add :team_id, references(:assignment_teams, on_delete: :restrict)
      add :accepted_at, :utc_datetime_usec, null: false
      add :extension_until, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:assignment_subjects, :assignment_subjects_kind_check,
             check:
               "(kind = 'individual' AND user_id IS NOT NULL AND team_id IS NULL) OR (kind = 'team' AND team_id IS NOT NULL AND user_id IS NULL)"
           )

    create index(:assignment_subjects, [:assignment_id])

    create unique_index(:assignment_subjects, [:assignment_id, :user_id],
             where: "user_id IS NOT NULL"
           )

    create unique_index(:assignment_subjects, [:assignment_id, :team_id],
             where: "team_id IS NOT NULL"
           )

    create table(:assignment_invitations) do
      add :assignment_id, references(:assignments, on_delete: :delete_all), null: false
      add :created_by_id, references(:users, on_delete: :restrict), null: false
      add :token_hash, :binary, null: false
      add :token_encrypted, :binary, null: false
      add :expires_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:assignment_invitations, [:token_hash])
    create index(:assignment_invitations, [:assignment_id, :revoked_at])
    create unique_index(:assignment_invitations, [:assignment_id], where: "revoked_at IS NULL")

    create table(:assignment_repositories) do
      add :subject_id, references(:assignment_subjects, on_delete: :delete_all), null: false
      add :github_repository_id, :bigint
      add :owner_login, :string
      add :name, :string
      add :full_name, :string
      add :html_url, :string
      add :workflow_id, :bigint
      add :workflow_path, :string
      add :workflow_file_sha, :string
      add :state, :string, null: false, default: "pending"
      add :last_error, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:assignment_repositories, [:subject_id])

    create unique_index(:assignment_repositories, [:github_repository_id],
             where: "github_repository_id IS NOT NULL"
           )

    create constraint(:assignment_repositories, :assignment_repositories_state_check,
             check: "state IN ('pending', 'ready', 'failed')"
           )

    create table(:submission_pushes) do
      add :subject_id, references(:assignment_subjects, on_delete: :delete_all), null: false

      add :repository_id, references(:assignment_repositories, on_delete: :delete_all),
        null: false

      add :commit_sha, :string, null: false
      add :branch, :string
      add :observed_at, :utc_datetime_usec, null: false
      add :delivery_id, :string, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:submission_pushes, [:delivery_id])
    create index(:submission_pushes, [:repository_id, :observed_at])
    create index(:submission_pushes, [:subject_id, :observed_at])

    create constraint(:submission_pushes, :submission_pushes_sha_check,
             check: "length(commit_sha) BETWEEN 40 AND 64"
           )

    create table(:autograding_results) do
      add :subject_id, references(:assignment_subjects, on_delete: :delete_all), null: false

      add :repository_id, references(:assignment_repositories, on_delete: :delete_all),
        null: false

      add :commit_sha, :string, null: false
      add :run_id, :bigint, null: false
      add :run_attempt, :integer, null: false, default: 1
      add :status, :string, null: false
      add :score, :decimal, precision: 8, scale: 2, null: false
      add :max_score, :decimal, precision: 8, scale: 2, null: false
      add :html_url, :string
      add :reason, :string
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:autograding_results, [:repository_id, :run_id, :run_attempt])
    create index(:autograding_results, [:subject_id, :inserted_at])

    create index(:autograding_results, [:subject_id, :commit_sha, :run_id, :run_attempt],
             name: :autograding_results_latest_commit_index
           )

    create constraint(:autograding_results, :autograding_results_run_attempt_positive,
             check: "run_attempt > 0"
           )

    create constraint(:autograding_results, :autograding_results_sha_check,
             check: "length(commit_sha) BETWEEN 40 AND 64"
           )

    create constraint(:autograding_results, :autograding_results_status_check,
             check:
               "status IN ('success', 'failure', 'cancelled', 'timed_out', 'queued', 'in_progress', 'untrusted')"
           )

    create constraint(:autograding_results, :autograding_results_reason_check,
             check: "reason IS NULL OR reason IN ('workflow_modified')"
           )

    create constraint(:autograding_results, :autograding_results_untrusted_score_check,
             check: "status != 'untrusted' OR (score = 0 AND max_score = 0)"
           )

    create constraint(:autograding_results, :autograding_results_score_check,
             check: "score >= 0 AND max_score >= 0 AND score <= max_score"
           )

    create table(:autograding_test_results) do
      add :result_id, references(:autograding_results, on_delete: :delete_all), null: false
      add :assignment_test_id, references(:assignment_tests, on_delete: :restrict), null: false
      add :name, :string, null: false
      add :status, :string, null: false
      add :points_awarded, :decimal, precision: 8, scale: 2, null: false, default: 0
      add :max_points, :decimal, precision: 8, scale: 2, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:autograding_test_results, [:result_id])
    create index(:autograding_test_results, [:assignment_test_id])

    create constraint(:autograding_test_results, :autograding_test_results_status_check,
             check: "status IN ('success', 'failure', 'cancelled', 'skipped')"
           )

    create constraint(:autograding_test_results, :autograding_test_results_score_check,
             check: "points_awarded >= 0 AND max_points >= 0 AND points_awarded <= max_points"
           )
  end
end
