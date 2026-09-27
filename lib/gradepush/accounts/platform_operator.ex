defmodule GradePush.Accounts.PlatformOperator do
  @moduledoc false
  use Ecto.Schema

  alias GradePush.Accounts.User

  schema "platform_operators" do
    belongs_to :user, User
    belongs_to :added_by, User
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
