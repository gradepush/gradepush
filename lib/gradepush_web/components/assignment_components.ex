defmodule GradePushWeb.AssignmentComponents do
  @moduledoc false
  use GradePushWeb, :html

  alias GradePushWeb.ClassroomComponents
  alias GradePushWeb.Markdown

  attr :assignment, :map, required: true
  attr :classroom, :map, required: true
  attr :locale, :string, required: true
  attr :query, :string, default: ""
  attr :filter, :string, default: "all"
  attr :tab, :string, default: "submissions"
  attr :preview, :boolean, default: true
  attr :teams, :list, default: []
  attr :members, :list, default: []

  attr :details, :map, required: true

  def page(assigns) do
    assigns = assign(assigns, assigns.details)

    assigns =
      assigns
      |> assign_new(:accepted, fn -> assigns.assignment.submitted end)
      |> assign_new(:total, fn -> assigns.classroom.students end)
      |> assign(:activity_max, max_activity_count(assigns.details.rows))

    ~H"""
    <ClassroomComponents.breadcrumbs items={[
      {gettext("Classrooms"), "/classrooms"},
      {local(@classroom.title, @locale), "/classrooms/#{@classroom.slug}"},
      {local(@assignment.title, @locale), nil}
    ]} />
    <div class="cp-assignment-overview">
      <div class="cp-heading cp-assignment-heading">
        <div>
          <p class="cp-context">{gettext("Assignment")}</p><h1>
            {local(@assignment.title, @locale)}
          </h1>
        </div>
        <div class="cp-assignment-actions">
          <a
            :if={!@preview}
            class="cp-button"
            href={"/classrooms/#{@classroom.slug}/assignments/#{@assignment.key}/export.csv"}
            download
          ><.icon name="hero-arrow-down-tray" class="size-4" />{gettext("Export CSV")}</a>
          <.link
            class="cp-button"
            patch={"/classrooms/#{@classroom.slug}/assignments/#{@assignment.key}/edit"}
          ><.icon name="hero-pencil-square" class="size-4" />{gettext("Edit assignment")}</.link>
          <button
            class="cp-button cp-primary"
            phx-click={JS.push_focus() |> JS.push("open", value: %{kind: "assignment_invite"})}
          ><.icon name="hero-link" class="size-4" />{gettext("Share assignment")}</button>
        </div>
      </div>
      <div class="cp-assignment-facts">
        <span><.icon
          name={if @assignment.group?, do: "hero-user-group", else: "hero-user"}
          class="size-4"
        />{local(@assignment.kind, @locale)}</span>
        <span><.icon name="hero-calendar-days" class="size-4" />{if not has_deadline?(
                                                                      @assignment,
                                                                      @preview
                                                                    ),
                                                                    do: gettext("No deadline"),
                                                                    else:
                                                                      gettext("Due %{date}",
                                                                        date:
                                                                          local(
                                                                            @assignment.due,
                                                                            @locale
                                                                          )
                                                                      )}</span>
        <span :if={@assignment.tests?}><.icon name="hero-check-circle" class="size-4" />{gettext(
          "%{count} automatic tests",
          count: length(@tests)
        )}</span>
        <span :if={@assignment[:cutoff]}><.icon name="hero-lock-closed" class="size-4" />{gettext(
          "Pushes close at the deadline"
        )}</span>
      </div>
      <div class="cp-acceptance-overview">
        <svg viewBox="0 0 64 64" aria-hidden="true" class="cp-acceptance-ring">
          <circle cx="32" cy="32" r="27" class="cp-ring-track" />
          <circle
            cx="32"
            cy="32"
            r="27"
            class="cp-ring-progress"
            pathLength="100"
            stroke-dasharray={"#{if @total > 0, do: min(100, @accepted / @total * 100), else: 0} 100"}
          />
        </svg>
        <div>
          <strong>{@accepted}<span> / {@total}</span></strong><p>
            {gettext("%{accepted} of %{total} students have accepted",
              accepted: @accepted,
              total: @total
            )}
          </p>
        </div>
      </div>
    </div>
    <details class="cp-instructions" id={"instructions-#{@assignment.key}"}>
      <summary>
        <h2>{gettext("Assignment instructions")}</h2><.icon name="hero-chevron-down" class="size-4" />
      </summary>
      <div class="cp-instructions-content cp-markdown">
        {Markdown.render(@instructions, 2)}
        <h3>{gettext("Getting started")}</h3>
        <ol>
          <li>{gettext("Accept the assignment to get your repository.")}</li><li>
            {gettext("Clone the repository and follow the README instructions.")}
          </li><li>{gettext("Commit and push your work to GitHub as you go.")}</li>
        </ol>
        <p :if={@assignment.tests?}>
          {gettext(
            "Tests run on each push. Open GitHub Actions in your repository to see the results."
          )}
        </p>
      </div>
    </details>
    <nav class="cp-tabs cp-assignment-tabs" aria-label={gettext("Assignment sections")}>
      <.link
        patch={"/classrooms/#{@classroom.slug}/assignments/#{@assignment.key}"}
        aria-current={if @tab == "submissions", do: "page"}
        class={if @tab == "submissions", do: "is-active"}
      ><.icon name="hero-inbox-arrow-down" class="size-4" />{gettext("Submissions")}</.link>
      <.link
        patch={"/classrooms/#{@classroom.slug}/assignments/#{@assignment.key}?view=tests"}
        aria-current={if @tab == "tests", do: "page"}
        class={if @tab == "tests", do: "is-active"}
      ><.icon name="hero-beaker" class="size-4" />{gettext("Tests")}<span class="cp-tab-count">{length(
        @tests
      )}</span></.link>
    </nav>
    <section
      :if={@tab == "submissions"}
      aria-labelledby="assignment-submissions-title"
      class="cp-submissions"
    >
      <div class="cp-submissions-heading">
        <h2 id="assignment-submissions-title">
          {if @assignment.group?, do: gettext("Teams"), else: gettext("Students")}
        </h2><span>{gettext("%{accepted} of %{total} students have accepted",
          accepted: @accepted,
          total: @total
        )}</span>
        <button
          class="cp-button"
          phx-click={JS.push_focus() |> JS.push("open", value: %{kind: "clone_all"})}
        ><.icon name="hero-command-line" class="size-4" />{gettext("Clone all locally")}</button>
        <button
          :if={teacher_managed_teams?(@assignment, @preview)}
          class="cp-button"
          phx-click={JS.push_focus() |> JS.push("open", value: %{kind: "teams"})}
        ><.icon name="hero-user-group" class="size-4" />{gettext("Manage teams")}</button>
      </div>
      <form
        id="submission-search"
        class="cp-submission-filters"
        phx-change="filter_submissions"
        role="search"
      >
        <label class="cp-search"><.icon name="hero-magnifying-glass" class="size-4" /><span class="sr-only">{gettext(
          "Search by name or student ID"
        )}</span><input
          name="query"
          type="search"
          placeholder={gettext("Search by name or student ID")}
          value={@query}
          phx-debounce="150"
        /></label>
        <label class="cp-status-filter"><span class="sr-only">{gettext("Filter by progress")}</span><select name="status"><option
          value="all"
          selected={@filter == "all"}
        >
          {gettext("All progress")}
        </option><option
          :for={status <- [:pushed, :late, :no_push, :not_accepted]}
          :if={!@assignment.group? or status != :not_accepted}
          value={status}
          selected={@filter == to_string(status)}
        >
          {status_label(status)}
        </option></select></label>
      </form>
      <div :if={@rows != []} class="cp-submission-table-wrap">
        <table class="cp-submission-table">
          <caption class="sr-only">
            {gettext("Repositories and progress for this assignment")}
          </caption>
          <thead>
            <tr>
              <th scope="col">
                {if @assignment.group?, do: gettext("Team"), else: gettext("Student")}
              </th><th scope="col">
                {gettext("Last push")}
              </th><th scope="col">{gettext("Activity")}</th><th :if={@assignment.tests?} scope="col">
                {gettext("Test score")}
              </th><th scope="col" class="cp-submission-actions-heading">
                {gettext("Actions")}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @rows} id={"submission-#{row.key}"}>
              <th scope="row" class="cp-submission-person">
                <strong>{row.name}</strong>
                <span :if={!@assignment.group?}>{row.identifier} ·
                <a
                  href={"https://github.com/#{row.handle}"}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="cp-profile-link"
                >@{row.handle}</a></span>
                <span :if={@assignment.group?} class="cp-team-profiles"><a
                  :for={member <- row.member_profiles}
                  href={"https://github.com/#{member.handle}"}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="cp-profile-link"
                >{member.name}</a></span>
              </th>
              <td class="cp-push-cell" data-label={gettext("Last push")}>
                <span :if={row.pushed}>{local(row.pushed, @locale)}</span><.dash
                  :if={!row.pushed}
                  label={gettext("No pushes")}
                />
                <span :if={row.status == :late} class="cp-late-note">{gettext("Late")}</span>
              </td>
              <td class="cp-activity-cell" data-label={gettext("Activity")}>
                <.activity
                  counts={row.activity}
                  dates={@dates}
                  max_count={@activity_max}
                  preview={@preview}
                />
              </td>
              <td :if={@assignment.tests?} class="cp-tests-cell" data-label={gettext("Test score")}>
                <span :if={row.score != nil} class="cp-test-score">{row.score}<span> / {@total_points}</span></span>
                <span
                  :if={Map.get(row, :grade_untrusted?, false)}
                  class="cp-late-note"
                  title={gettext("The grading workflow changed. This result cannot be verified.")}
                >{gettext("Workflow changed")}</span>
                <.dash
                  :if={row.score == nil and not Map.get(row, :grade_untrusted?, false)}
                  label={gettext("Not run")}
                />
                <button
                  :if={!@preview and Map.get(row, :subject_id)}
                  class="cp-profile-link cp-results-link"
                  phx-click={
                    JS.push_focus()
                    |> JS.push("open", value: %{kind: "test_results", subject_id: row.subject_id})
                  }
                  aria-label={gettext("View test results for %{name}", name: row.name)}
                >{gettext("View results")}</button>
              </td>
              <td class="cp-submission-actions-cell">
                <div class="cp-submission-actions">
                  <a
                    :if={!@preview and row.repository_url}
                    class="cp-button cp-repository-button"
                    href={row.repository_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    aria-label={gettext("Open repository %{repository}", repository: row.repository)}
                  ><.icon name="hero-arrow-top-right-on-square" class="size-4" />{gettext(
                    "Repository"
                  )}</a><button
                    :if={@preview and row.repository}
                    class="cp-button cp-repository-button"
                    disabled
                    title={gettext("Repository links are unavailable in this preview.")}
                    aria-label={gettext("Open repository %{repository}", repository: row.repository)}
                  ><.icon name="hero-arrow-top-right-on-square" class="size-4" />{gettext(
                    "Repository"
                  )}</button>
                  <button
                    :if={
                      not @preview and not is_nil(Map.get(row, :subject_id)) and
                        not is_nil(@assignment.deadline_at)
                    }
                    class="cp-extension-button"
                    phx-click={
                      JS.push_focus()
                      |> JS.push("open",
                        value: %{kind: "deadline_extension", subject_id: Map.get(row, :subject_id)}
                      )
                    }
                    title={
                      if Map.get(row, :extension_until) not in [nil, ""],
                        do: gettext("Change deadline"),
                        else: gettext("Extend deadline")
                    }
                    aria-label={gettext("Revise deadline for %{name}", name: row.name)}
                  ><.icon name="hero-calendar-days" class="size-4" /></button>
                </div>
                <p :if={Map.get(row, :repository_state) == "pending"} class="cp-field-help">
                  {gettext("Repository is being created.")}
                </p>
                <div
                  :if={!@preview and Map.get(row, :repository_state) == "failed"}
                  class="cp-repository-error"
                >
                  <p>{Map.get(row, :repository_error)}</p>
                  <button
                    class="cp-button"
                    phx-click="retry_repository"
                    phx-value-subject_id={row.subject_id}
                    aria-label={gettext("Retry repository setup for %{name}", name: row.name)}
                  ><.icon name="hero-arrow-path" class="size-4" />{gettext("Retry setup")}</button>
                </div>
                <p :if={Map.get(row, :extension_label)} class="cp-late-note">
                  {gettext("Deadline extended to %{date}",
                    date: local(Map.get(row, :extension_label), @locale)
                  )}
                </p>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <div :if={@rows == []} class="cp-empty">
        <.icon name="hero-user-group" class="size-8" /><h3>
          {if @assignment.group? and @assignment.submitted == 0,
            do: gettext("No teams yet"),
            else: gettext("No matching results")}
        </h3><p>
          {empty_message(@assignment, @teams)}
        </p>
      </div>
      <p :if={@assignment.group?} class="cp-group-note">
        {gettext("One shared repository per team.")}
      </p>
      <p :if={@preview} class="cp-preview-note">
        {gettext("Repository links are unavailable in this preview.")}
      </p>
    </section>
    <section :if={@tab == "tests"} class="cp-test-catalog" aria-labelledby="test-catalog-title">
      <div class="cp-submissions-heading">
        <h2 id="test-catalog-title">{gettext("Automatic tests")}</h2>
        <span :if={@tests != []}>
          {gettext("%{points} points total", points: @total_points)}
        </span>
      </div>
      <p :if={@tests != []} class="cp-lead">
        {gettext(
          "These tests run in GitHub Actions on each push. The score is the sum of the points earned."
        )}
      </p>
      <ol :if={@tests != []} class="cp-test-list">
        <li :for={test <- @tests}>
          <div>
            <h3>{test.name}</h3><p :if={test.description not in [nil, ""]}>
              {test.description}
            </p>
            <code :if={test[:type]} class="cp-test-command">{if test.type == "file",
              do: test.path,
              else: test.command}</code>
            <div :if={test[:type] == "io"} class="cp-test-io">
              <p>{gettext("Standard input (optional)")}</p><pre>{test.input || ""}</pre><p>
                {gettext("Expected output")}
              </p><pre>{test.expected}</pre>
            </div>
          </div><span>{gettext("%{points} points", points: test.points)}</span>
        </li>
      </ol>
      <div :if={@tests == []} class="cp-empty">
        <.icon name="hero-beaker" class="size-8" /><h3>{gettext("No automatic tests")}</h3><p>
          {gettext("This assignment has no automatic test score.")}
        </p>
      </div>
    </section>
    """
  end

  attr :label, :string, required: true

  defp dash(assigns) do
    ~H"""
    <span class="cp-dash" aria-label={@label}>—</span>
    """
  end

  attr :counts, :list, required: true
  attr :dates, :list, required: true
  attr :max_count, :integer, required: true
  attr :preview, :boolean, required: true

  defp activity(assigns) do
    samples =
      Enum.with_index(assigns.counts, fn count, index ->
        y = if count == 0, do: 30, else: 30 - round(count / assigns.max_count * 28)
        %{x: 3 + index * 8, y: y, count: count, date: Enum.at(assigns.dates, index)}
      end)

    summary =
      Enum.map_join(samples, "; ", &"#{GradePushWeb.Presentation.date(&1.date)}: #{&1.count}")

    label = if assigns.preview, do: daily_commits(summary), else: daily_pushes(summary)
    empty_label = if assigns.preview, do: gettext("No commits"), else: gettext("No pushes")

    assigns =
      assign(assigns,
        samples: samples,
        points: Enum.map_join(samples, " ", &"#{&1.x},#{&1.y}"),
        summary: label,
        empty_label: empty_label
      )

    ~H"""
    <svg
      :if={@counts != []}
      class="cp-sparkline"
      viewBox="0 0 110 34"
      role="img"
      tabindex="0"
      aria-label={@summary}
    ><title>{@summary}</title><path d="M3 30H107" class="cp-sparkline-base" /><polyline points={
      @points
    } /><circle :for={sample <- @samples} :if={sample.count > 0} cx={sample.x} cy={sample.y} r="2">
      <title>{GradePushWeb.Presentation.date(sample.date)}: {sample.count}</title>
    </circle></svg>
    <.dash :if={@counts == []} label={@empty_label} />
    """
  end

  defp status_label(:pushed), do: gettext("Work pushed")
  defp status_label(:late), do: gettext("Late")
  defp status_label(:no_push), do: gettext("No pushes")
  defp status_label(:not_accepted), do: gettext("Not accepted")

  defp empty_message(%{group?: true, submitted: 0, team_mode: "teacher"}, teams)
       when teams != [],
       do: gettext("Students will see their assigned team when they accept the assignment.")

  defp empty_message(%{group?: true, submitted: 0, team_mode: "teacher"}, _teams),
    do: gettext("No teams have been assigned yet.")

  defp empty_message(%{group?: true, submitted: 0}, _teams),
    do: gettext("Students will create or join a team when they accept the assignment.")

  defp empty_message(_, _teams), do: gettext("Try another search or progress filter.")

  defp teacher_managed_teams?(%{group?: true, team_mode: "teacher"}, false), do: true
  defp teacher_managed_teams?(_, _), do: false

  defp max_activity_count(rows) do
    rows
    |> Enum.flat_map(&(Map.get(&1, :activity) || []))
    |> Enum.max(fn -> 0 end)
    |> max(1)
  end

  defp daily_commits(summary), do: gettext("Daily commits: %{counts}", counts: summary)
  defp daily_pushes(summary), do: gettext("Daily pushes: %{counts}", counts: summary)

  defp has_deadline?(assignment, true), do: Map.get(assignment, :status) != :draft
  defp has_deadline?(assignment, false), do: not is_nil(Map.get(assignment, :deadline_at))

  defp local(text, locale), do: Map.fetch!(text, String.to_existing_atom(locale))
end
