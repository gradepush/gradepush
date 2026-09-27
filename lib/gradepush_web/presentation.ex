defmodule GradePushWeb.Presentation do
  @moduledoc false

  alias GradePush.Accounts

  def user(user) do
    name = Map.get(user, :student_name) || user.name
    name = if name in [nil, ""], do: user.login, else: name

    %{
      id: user.id,
      name: name,
      handle: user.login,
      initials: initials(name),
      avatar_url: user.avatar_url,
      identifier: user.student_id || "",
      color: "blue"
    }
  end

  def initials(name) do
    name
    |> String.split()
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  def text(value), do: %{en: value || "", fr: value || ""}

  def contexts(user) do
    roles = Accounts.institution_roles(user)
    operator? = Accounts.operator?(user)

    if(:teacher in roles, do: [:teaching], else: []) ++
      if(:student in roles or (roles == [] and not operator?), do: [:learning], else: []) ++
      if(:admin in roles, do: [:institution], else: []) ++
      if(operator?, do: [:platform], else: [])
  end

  def datetime(nil), do: "—"
  def datetime(value), do: GradePush.Time.format_datetime(value)
end
