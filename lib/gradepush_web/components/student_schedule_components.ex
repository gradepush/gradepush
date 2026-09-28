defmodule GradePushWeb.StudentScheduleComponents do
  @moduledoc "Student assignment agenda and localized deadline calendar."
  use GradePushWeb, :html

  alias GradePushWeb.Presentation

  def prepare(entries, params, now \\ DateTime.utc_now()) do
    today = local_date(now)
    month = parse_month(params["month"], today)
    {undated, dated} = Enum.split_with(entries, &is_nil(&1.deadline_at))
    {past, upcoming} = Enum.split_with(dated, &(DateTime.compare(&1.deadline_at, now) == :lt))
    by_date = Enum.group_by(dated, &local_date(&1.deadline_at))
    first = Date.add(month, 1 - Date.day_of_week(month))
    last = Date.end_of_month(month)
    last = Date.add(last, 7 - Date.day_of_week(last))

    %{
      view: if(params["view"] == "calendar", do: "calendar", else: "list"),
      month: month,
      today: today,
      empty?: entries == [],
      upcoming: upcoming,
      past: Enum.reverse(past),
      undated: undated,
      days:
        by_date
        |> Enum.filter(fn {date, _} -> date.year == month.year and date.month == month.month end)
        |> Enum.sort_by(fn {date, _} -> Date.to_gregorian_days(date) end),
      weeks:
        Date.range(first, last)
        |> Enum.map(fn date ->
          in_month? = date.year == month.year and date.month == month.month

          %{
            date: date,
            current?: in_month?,
            entries: if(in_month?, do: by_date[date] || [], else: [])
          }
        end)
        |> Enum.chunk_every(7)
    }
  end

  defp local_date(datetime),
    do: datetime |> DateTime.shift_zone!(GradePush.Time.timezone()) |> DateTime.to_date()

  defp parse_month(value, today) when is_binary(value) do
    case Date.from_iso8601(value <> "-01") do
      {:ok, %{year: year} = date} when year in 1900..2100 -> date
      _ -> Date.beginning_of_month(today)
    end
  end

  defp parse_month(_, today), do: Date.beginning_of_month(today)

  defp schedule_path(view, month),
    do:
      "/student/assignments?" <>
        URI.encode_query(%{view: view, month: Calendar.strftime(month, "%Y-%m")})

  defp assignment_path(entry),
    do: "/student/classrooms/#{entry.classroom.slug}/assignments/#{entry.assignment.slug}"

  attr :schedule, :map, required: true

  def schedule(assigns) do
    ~H"""
    <.page_heading>
      <div>
        <.eyebrow>{gettext("Learning")}</.eyebrow>
        <h1>{gettext("My assignments")}</h1>
        <.lead>{gettext("All your classes, ordered by deadline.")}</.lead>
      </div>
    </.page_heading>
    <.tabs id="schedule-views" label={gettext("Assignment view")} class="mb-[28px]">
      <.tab patch={schedule_path("list", @schedule.month)} active={@schedule.view == "list"}>
        <.icon name="hero-list-bullet" />{gettext("List")}
      </.tab>
      <.tab patch={schedule_path("calendar", @schedule.month)} active={@schedule.view == "calendar"}>
        <.icon name="hero-calendar-days" />{gettext("Calendar")}
      </.tab>
    </.tabs>
    <%= cond do %>
      <% @schedule.empty? -> %>
        <.empty_state>
          <.icon name="hero-document-text" class="size-8" />
          <h2>{gettext("No assignments yet")}</h2>
          <p>{gettext("Assignments from your classes will appear here.")}</p>
          <.button navigate="/student/classrooms">{gettext("My classrooms")}</.button>
        </.empty_state>
      <% @schedule.view == "calendar" -> %>
        <.calendar schedule={@schedule} />
        <.assignment_group
          :if={@schedule.undated != []}
          id="undated-assignments"
          title={gettext("No deadline")}
          entries={@schedule.undated}
        />
      <% true -> %>
        <.assignment_group
          id="upcoming-assignments"
          title={gettext("Upcoming deadlines")}
          entries={@schedule.upcoming}
        />
        <.assignment_group
          :if={@schedule.undated != []}
          id="undated-assignments"
          title={gettext("No deadline")}
          entries={@schedule.undated}
        />
        <.assignment_group
          :if={@schedule.past != []}
          id="past-assignments"
          title={gettext("Past deadlines")}
          entries={@schedule.past}
        />
    <% end %>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :entries, :list, required: true

  defp assignment_group(assigns) do
    ~H"""
    <section id={@id} aria-labelledby={@id <> "-heading"} class="mb-[32px]">
      <.list_toolbar>
        <h2 id={@id <> "-heading"}>{@title}</h2>
        <span class="text-[13px] text-muted">{length(@entries)}</span>
      </.list_toolbar>
      <.empty_state :if={@entries == []}>
        <p>{gettext("No upcoming deadlines.")}</p>
      </.empty_state>
      <.data_list :if={@entries != []}>
        <.list_header kind="student_assignments">
          <span>{gettext("Assignment")}</span><span>{gettext("Classroom")}</span><span>{gettext(
            "Deadline"
          )}</span>
        </.list_header>
        <.list_row :for={entry <- @entries} kind="student_assignments" patch={assignment_path(entry)}>
          <div class="flex min-w-0 items-center gap-[14px] max-[760px]:col-span-full">
            <.icon name="hero-document-text" class="size-5 shrink-0 text-icon" />
            <h3>{entry.assignment.title}</h3>
          </div>
          <div class="min-w-0 wrap-anywhere text-[13px] text-caption">
            <span class="block text-[11px] font-semibold text-muted">{entry.classroom.code}</span>
            {entry.classroom.title}
          </div>
          <div class="min-w-0 wrap-anywhere text-[13px] text-caption">
            <span class="hidden text-[11px] text-muted max-[760px]:block">{gettext("Deadline")}</span>
            <.deadline value={entry.deadline_at} />
          </div>
        </.list_row>
      </.data_list>
    </section>
    """
  end

  attr :value, :any, required: true

  defp deadline(assigns) do
    ~H"""
    <time :if={@value} datetime={DateTime.to_iso8601(@value)}>{Presentation.datetime(@value)}</time>
    <span :if={!@value}>{gettext("No deadline")}</span>
    """
  end

  attr :schedule, :map, required: true

  defp calendar(assigns) do
    assigns =
      assign(assigns,
        previous: Date.beginning_of_month(Date.add(assigns.schedule.month, -1)),
        next: Date.add(Date.end_of_month(assigns.schedule.month), 1),
        weekdays: [
          gettext("Monday"),
          gettext("Tuesday"),
          gettext("Wednesday"),
          gettext("Thursday"),
          gettext("Friday"),
          gettext("Saturday"),
          gettext("Sunday")
        ]
      )

    ~H"""
    <section aria-labelledby="calendar-heading" class="mb-[32px]">
      <div class="mb-[20px] flex flex-wrap items-center justify-between gap-[16px]">
        <h2 id="calendar-heading" aria-live="polite" class="text-[20px] font-semibold capitalize">
          {Presentation.month(@schedule.month)}
        </h2>
        <nav aria-label={gettext("Calendar month")} class="flex items-center gap-[8px]">
          <.button patch={schedule_path("calendar", @schedule.today)}>{gettext("Today")}</.button>
          <.button
            :if={@previous.year >= 1900}
            patch={schedule_path("calendar", @previous)}
            aria-label={gettext("Previous month")}
          ><.icon name="hero-chevron-left" /></.button>
          <.button
            :if={@next.year <= 2100}
            patch={schedule_path("calendar", @next)}
            aria-label={gettext("Next month")}
          ><.icon name="hero-chevron-right" /></.button>
        </nav>
      </div>
      <div class="overflow-hidden rounded-[12px] border border-panel bg-white max-[1000px]:hidden">
        <table id="deadline-calendar" class="w-full table-fixed border-collapse">
          <caption class="sr-only">
            {gettext("Assignment deadlines for %{month}", month: Presentation.month(@schedule.month))}
          </caption>
          <.list_header kind="table">
            <tr>
              <th :for={day <- @weekdays} scope="col" class="px-[8px] py-[14px] text-left">{day}</th>
            </tr>
          </.list_header>
          <tbody>
            <tr :for={week <- @schedule.weeks}>
              <td
                :for={day <- week}
                class={[
                  "h-[140px] border-t border-r border-line p-[8px] align-top last:border-r-0",
                  !day.current? && "bg-surface-heading"
                ]}
              >
                <time
                  datetime={Date.to_iso8601(day.date)}
                  aria-current={if day.date == @schedule.today, do: "date"}
                  aria-label={Presentation.date(day.date)}
                  class={[
                    "mb-[8px] inline-flex size-[28px] items-center justify-center rounded-full text-[12px]",
                    if(day.date == @schedule.today,
                      do: "bg-brand font-semibold text-white",
                      else: if(day.current?, do: "text-ink", else: "text-faint")
                    )
                  ]}
                >{day.date.day}</time>
                <.link
                  :for={entry <- day.entries}
                  patch={assignment_path(entry)}
                  aria-label={"#{entry.assignment.title}, #{entry.classroom.title}, #{Presentation.datetime(entry.deadline_at)}"}
                  class="mb-[6px] block wrap-anywhere rounded-[6px] border border-brand/10 bg-brand-soft p-[8px] text-[12px] leading-[1.4] hover:border-brand-outline hover:bg-white"
                >
                  <span class="block text-[10px] font-semibold text-muted">{entry.classroom.code}</span>
                  <span class="my-[4px] block wrap-anywhere font-semibold text-brand-strong">{entry.assignment.title}</span>
                  <span class="text-muted">{entry.deadline_at
                  |> DateTime.shift_zone!(GradePush.Time.timezone())
                  |> Calendar.strftime("%H:%M")}</span>
                </.link>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <.empty_state :if={@schedule.days == []}>
        <p>{gettext("No deadlines this month.")}</p>
      </.empty_state>
      <div class="hidden max-[1000px]:block">
        <.assignment_group
          :for={{date, entries} <- @schedule.days}
          id={"day-#{Date.to_iso8601(date)}"}
          title={Presentation.date(date)}
          entries={entries}
        />
      </div>
    </section>
    """
  end
end
