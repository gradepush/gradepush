defmodule GradePushWeb.Presentation do
  @moduledoc false
  use Gettext, backend: GradePushWeb.Gettext

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

  def classroom_term(%{semester: semester, academic_year: year})
      when semester in ["winter", "summer", "fall"] and is_binary(year) and year != "",
      do: "#{semester_label(semester)} #{year}"

  def classroom_term(classroom), do: Map.get(classroom, :session) || ""

  def semester_options,
    do: Enum.map(~w(winter summer fall), &{semester_label(&1), &1})

  def classroom_groups(classrooms) do
    classrooms
    |> Enum.group_by(&term_key/1)
    |> Enum.sort_by(fn {key, _} -> group_sort_key(key) end, :desc)
    |> Enum.map(fn {_key, classes} ->
      label = classroom_term(hd(classes))
      %{label: if(label == "", do: gettext("No semester"), else: label), classes: classes}
    end)
  end

  defp term_key(%{semester: semester, academic_year: year})
       when semester in ["winter", "summer", "fall"] and is_binary(year) and year != "",
       do: {:structured, semester, year}

  defp term_key(classroom), do: {:legacy, classroom_term(classroom)}

  defp group_sort_key({:structured, semester, year}) do
    {year_rank, sortable_year} = sortable_year(year)
    {year_rank, sortable_year, Enum.find_index(~w(winter summer fall), &(&1 == semester)), year}
  end

  defp group_sort_key({:legacy, ""}), do: {0, 0, 0, ""}
  defp group_sort_key({:legacy, label}), do: {1, 0, 0, label}

  defp sortable_year(year) do
    cond do
      Regex.match?(~r/^[0-9]{2}$/, year) -> {2, 2000 + String.to_integer(year)}
      Regex.match?(~r/^[0-9]{4}$/, year) -> {2, String.to_integer(year)}
      true -> {1, 0}
    end
  end

  defp semester_label("winter"), do: gettext("Winter")
  defp semester_label("summer"), do: gettext("Summer")
  defp semester_label("fall"), do: gettext("Fall")

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
