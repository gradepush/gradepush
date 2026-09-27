defmodule GradePush.Accounts.AuditEvent do
  @moduledoc false
  use Ecto.Schema

  alias GradePush.Accounts.User

  schema "administrative_audit_events" do
    field :scope, Ecto.Enum, values: [:institution, :platform]
    field :action, :string
    field :target_type, :string
    field :target_id, :integer
    field :target_label, :string
    field :metadata, :map, default: %{}
    field :actor_name, :string, virtual: true
    field :target, :string, virtual: true
    belongs_to :actor, User
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
