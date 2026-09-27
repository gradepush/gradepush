defmodule GradePush.Accounts.Institution do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @footer_fields [:support_url, :privacy_url, :accessibility_url, :terms_url]

  schema "institutions" do
    field :singleton_key, :boolean, default: true
    field :name, :string
    field :time_zone, :string, default: "America/Toronto"
    field :support_url, :string
    field :privacy_url, :string
    field :accessibility_url, :string
    field :terms_url, :string

    timestamps(type: :utc_datetime_usec)
  end

  def footer_fields, do: @footer_fields

  def footer_changeset(institution, attrs) do
    changeset = cast(institution, attrs, @footer_fields)

    Enum.reduce(@footer_fields, changeset, fn field, changeset ->
      changeset
      |> update_change(field, &trim_url/1)
      |> validate_length(field, max: 2_048)
      |> validate_change(field, &validate_footer_url/2)
    end)
  end

  defp trim_url(nil), do: nil
  defp trim_url(value), do: String.trim(value)

  defp validate_footer_url(field, value) do
    if valid_footer_url?(value, field), do: [], else: [{field, "is invalid"}]
  end

  defp valid_footer_url?(value, field) do
    with false <- String.contains?(value, ["\\", "\r", "\n", "\t", " "]),
         {:ok, uri} <- URI.new(value) do
      case uri do
        %URI{scheme: "https", host: host, userinfo: nil} when is_binary(host) and host != "" ->
          true

        %URI{scheme: "mailto", path: email, query: nil, fragment: nil, host: nil}
        when field == :support_url and is_binary(email) ->
          not String.contains?(email, "%") and Regex.match?(~r/\A[^@\s]+@[^@\s]+\z/, email)

        _ ->
          false
      end
    else
      _ -> false
    end
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
