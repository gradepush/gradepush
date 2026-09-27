defmodule GradePush.Accounts.Institution do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "institutions" do
    field :singleton_key, :boolean, default: true
    field :name, :string
    field :time_zone, :string, default: "America/Toronto"

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(institution, attrs) do
    institution
    |> cast(attrs, [:name, :time_zone])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :time_zone])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:time_zone, min: 1, max: 100)
    |> unique_constraint(:singleton_key)
  end
end
