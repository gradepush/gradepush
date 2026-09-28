defmodule GradePushWeb.Presentation do
  @moduledoc false
  use Gettext, backend: GradePushWeb.Gettext

  alias GradePush.Accounts
  alias GradePush.Classrooms.Classroom

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

  def points(%Decimal{} = value),
    do: value |> Decimal.round(0, :half_up) |> Decimal.to_string(:normal)

  def points(value) when is_float(value), do: value |> Decimal.from_float() |> points()
  def points(value) when is_integer(value), do: Integer.to_string(value)
  def points(value) when is_binary(value), do: value |> Decimal.new() |> points()

  def classroom_term(%{semester: semester, academic_year: year})
      when semester in [:winter, :summer, :fall] and is_binary(year) and year != "",
      do: "#{semester_label(semester)} #{year}"

  def classroom_term(_classroom), do: ""

  def semester_options,
    do:
      Enum.map(Ecto.Enum.values(Classroom, :semester), &{semester_label(&1), Atom.to_string(&1)})

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
       when semester in [:winter, :summer, :fall] and is_binary(year) and year != "",
       do: {semester, year}

  defp term_key(_classroom), do: nil

  defp group_sort_key({semester, year}) do
    {year_rank, sortable_year} = sortable_year(year)

    {year_rank, sortable_year, Keyword.fetch!(Ecto.Enum.mappings(Classroom, :semester), semester),
     year}
  end

  defp group_sort_key(nil), do: {0, 0, 0, ""}

  defp sortable_year(year) do
    cond do
      Regex.match?(~r/^[0-9]{2}$/, year) -> {2, 2000 + String.to_integer(year)}
      Regex.match?(~r/^[0-9]{4}$/, year) -> {2, String.to_integer(year)}
      true -> {1, 0}
    end
  end

  defp semester_label(:winter), do: gettext("Winter")
  defp semester_label(:summer), do: gettext("Summer")
  defp semester_label(:fall), do: gettext("Fall")

  def contexts(user) do
    roles = Accounts.institution_roles(user)
    operator? = Accounts.operator?(user)

    if(:teacher in roles, do: [:teaching], else: []) ++
      if(:student in roles or (roles == [] and not operator?), do: [:learning], else: []) ++
      if(:admin in roles, do: [:institution], else: []) ++
      if(operator?, do: [:platform], else: [])
  end

  def datetime(value, locale \\ Gettext.get_locale(GradePushWeb.Gettext))
  def datetime(nil, _locale), do: "—"

  def datetime(value, locale) do
    local =
      case value do
        %DateTime{} -> DateTime.shift_zone!(value, GradePush.Time.timezone())
        %NaiveDateTime{} -> value
      end

    time = Calendar.strftime(local, "%H:%M")

    case locale do
      "fr" -> "#{date(local, locale)} à #{time}"
      _ -> "#{date(local, locale)} at #{time}"
    end
  end

  def date(value, locale \\ Gettext.get_locale(GradePushWeb.Gettext)) do
    months =
      Gettext.with_locale(GradePushWeb.Gettext, locale, fn ->
        [
          gettext("January"),
          gettext("February"),
          gettext("March"),
          gettext("April"),
          gettext("May"),
          gettext("June"),
          gettext("July"),
          gettext("August"),
          gettext("September"),
          gettext("October"),
          gettext("November"),
          gettext("December")
        ]
      end)

    month = Enum.at(months, value.month - 1)

    if locale == "fr",
      do: "#{value.day} #{month} #{value.year}",
      else: "#{month} #{value.day}, #{value.year}"
  end

  def datetime_text(value), do: %{en: datetime(value, "en"), fr: datetime(value, "fr")}
end
