defmodule GradePush.Repo.Migrations.CreateIdentity do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :github_id, :bigint, null: false
      add :login, :string, null: false
      add :name, :string
      add :avatar_url, :string
      add :locale, :string, null: false, default: "en"
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:github_id])
    create unique_index(:users, ["lower(login)"], name: :users_login_lower_index)

    create table(:institutions) do
      add :singleton_key, :boolean, null: false, default: true
      add :name, :string, null: false
      add :time_zone, :string, null: false, default: "America/Toronto"
      add :support_url, :text
      add :privacy_url, :text
      add :accessibility_url, :text
      add :terms_url, :text
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:institutions, [:singleton_key])
    create constraint(:institutions, :institutions_singleton_key_true, check: "singleton_key")

    create table(:institution_memberships) do
      add :institution_id, references(:institutions, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :student_name, :string
      add :student_id, :string
      add :joined_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:institution_memberships, [:institution_id, :user_id, :role])

    create constraint(:institution_memberships, :institution_memberships_role_check,
             check: "role IN ('admin', 'teacher', 'student')"
           )

    create index(:institution_memberships, [:institution_id, :role])

    create table(:platform_operators) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :added_by_id, references(:users, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:platform_operators, [:user_id])

    create table(:user_sessions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :revoked_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:user_sessions, [:token_hash])
    create index(:user_sessions, [:user_id, :expires_at])

    create table(:github_apps) do
      add :singleton_key, :boolean, null: false, default: true
      add :app_id, :bigint, null: false
      add :client_id, :string, null: false
      add :client_secret_encrypted, :binary, null: false
      add :private_key_encrypted, :binary, null: false
      add :webhook_secret_encrypted, :binary, null: false
      add :slug, :string, null: false
      add :html_url, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:github_apps, [:singleton_key])
    create constraint(:github_apps, :github_apps_singleton_key_true, check: "singleton_key")

    create table(:github_user_credentials) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :access_token_encrypted, :binary, null: false
      add :refresh_token_encrypted, :binary
      add :expires_at, :utc_datetime_usec
      add :refresh_token_expires_at, :utc_datetime_usec
      add :scopes, {:array, :string}, null: false, default: []
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:github_user_credentials, [:user_id])

    create table(:institution_invitations) do
      add :institution_id, references(:institutions, on_delete: :delete_all), null: false
      add :invited_by_id, references(:users, on_delete: :nilify_all)
      add :accepted_by_id, references(:users, on_delete: :nilify_all)
      add :token_hash, :binary, null: false
      add :role, :string, null: false, default: "teacher"
      add :expires_at, :utc_datetime_usec, null: false
      add :accepted_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:institution_invitations, [:token_hash])
    create index(:institution_invitations, [:institution_id, :expires_at])

    create constraint(:institution_invitations, :institution_invitations_teacher_role,
             check: "role = 'teacher'"
           )

    create table(:administrative_audit_events) do
      add :scope, :string, null: false
      add :actor_id, references(:users, on_delete: :nilify_all)
      add :action, :string, null: false
      add :target_type, :string, null: false
      add :target_id, :bigint
      add :target_label, :string
      add :metadata, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:administrative_audit_events, [:scope, :inserted_at])
    create index(:administrative_audit_events, [:target_type, :target_id])

    create constraint(:administrative_audit_events, :administrative_audit_events_scope_check,
             check: "scope IN ('institution', 'platform')"
           )

    create table(:bootstrap_credentials, primary_key: false) do
      add :id, :integer, primary_key: true
      add :token_hash, :binary, null: false
      add :token_encrypted, :binary, null: false
      add :state_hash, :binary
      add :setup_browser_hash, :binary
      add :state_expires_at, :utc_datetime_usec
      add :institution_name, :string
      add :pending_app_encrypted, :binary
      add :step, :string, null: false, default: "setup"
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:bootstrap_credentials, [:token_hash])

    create constraint(:bootstrap_credentials, :bootstrap_credentials_singleton_id,
             check: "id = 1"
           )

    create constraint(:bootstrap_credentials, :bootstrap_credentials_step_check,
             check: "step IN ('setup', 'manifest', 'oauth')"
           )

    create table(:installation_modes, primary_key: false) do
      add :id, :integer, primary_key: true
      add :mode, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:installation_modes, :installation_modes_singleton_id, check: "id = 1")

    create constraint(:installation_modes, :installation_modes_mode_check,
             check: "mode IN ('self_hosted', 'demo')"
           )
  end
end
