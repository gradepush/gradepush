defmodule GradePush.Demo.InstanceMode do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "installation_modes" do
    field :mode, Ecto.Enum, values: [:self_hosted, :demo]
    timestamps(type: :utc_datetime_usec)
  end
end
