defmodule GradePush.Accounts.User do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :github_id, :integer
    field :login, :string
    field :name, :string
    field :avatar_url, :string
    field :locale, :string, default: "en"
    field :student_name, :string, virtual: true
    field :student_id, :string, virtual: true

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:github_id, :login, :name, :avatar_url, :locale])
    |> validate_required([:github_id, :login])
    |> validate_length(:login, min: 1, max: 39)
    |> validate_format(:login, ~r/\A[a-zA-Z0-9-]+\z/)
    |> validate_length(:name, max: 255)
    |> validate_length(:avatar_url, max: 2048)
    |> validate_inclusion(:locale, ~w(en fr))
    |> unique_constraint(:github_id)
    |> unique_constraint(:login, name: :users_login_lower_index)
  end
end
