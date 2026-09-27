defmodule GradePush.Installation.BootstrapCredential do
  @moduledoc false
  use Ecto.Schema

  schema "bootstrap_credentials" do
    field :token_hash, :binary
    field :token_encrypted, :binary
    field :state_hash, :binary
    field :setup_browser_hash, :binary
    field :state_expires_at, :utc_datetime_usec
    field :institution_name, :string
    field :pending_app_encrypted, :binary
    field :step, :string, default: "setup"
    timestamps(type: :utc_datetime_usec)
  end
end
