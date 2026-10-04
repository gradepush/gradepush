defmodule GradePushWeb.AssignmentComponents do
  @moduledoc false
  use GradePushWeb, :html

  alias GradePushWeb.ClassroomComponents
  alias GradePushWeb.Markdown
  alias GradePushWeb.Presentation

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
    <.overview kind="assignment">
      <.page_heading variant="assignment">
        <div>
          <.eyebrow>
            {gettext("Assignment")}
          </.eyebrow><h1>
            {local(@assignment.title, @locale)}
          </h1>
        </div>
        <div class={[
          "flex flex-wrap col-span-full row-start-3 pt-[22px] mt-[24px] border-t border-t-[#e5eaf3] justify-start",
          "gap-[10px] [&_[data-variant=primary]]:ml-auto max-[760px]:order-3 max-[760px]:grid",
          "max-[760px]:grid-cols-[1fr_1fr] max-[760px]:w-full max-[760px]:pt-[18px] max-[760px]:mt-[20px]",
          "max-[760px]:[&_[data-variant=primary]]:ml-0 max-[760px]:[&_[data-variant=primary]]:col-span-full"
        ]}>
          <.button
            :if={!@preview}
            compact_on_mobile
            href={"/classrooms/#{@classroom.slug}/assignments/#{@assignment.key}/export.csv"}
            download
          ><.icon name="hero-arrow-down-tray" class="size-4" />{gettext("Export CSV")}</.button>
          <.button
            compact_on_mobile
            patch={"/classrooms/#{@classroom.slug}/assignments/#{@assignment.key}/edit"}
          ><.icon
            name="hero-pencil-square"
            class="size-4"
          />{gettext("Edit assignment")}</.button>
          <.button
            compact_on_mobile
            variant="primary"
            phx-click={JS.push_focus() |> JS.push("open", value: %{kind: "assignment_invite"})}
          ><.icon name="hero-link" class="size-4" />{gettext("Share assignment")}</.button>
        </div>
      </.page_heading>
      <.assignment_facts>
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
        <span :if={@assignment.tests?}><.icon name="hero-check-circle" class="size-4" />{ngettext(
          "%{count} automatic test",
          "%{count} automatic tests",
          length(@tests)
        )}</span>
        <span :if={@assignment[:cutoff]}><.icon name="hero-lock-closed" class="size-4" />{gettext(
          "Pushes close at the deadline"
        )}</span>
      </.assignment_facts>
      <div class={[
        "col-start-2 row-[1_/_3] flex items-center border-l-[1px] [border-left-style:solid] border-l-[#e6ebf3]",
        "pl-[28px] gap-[17px] [&_strong]:block [&_strong]:text-[29px] [&_strong]:tracking-[-1px]",
        "[&_strong]:leading-[1.15] [&_strong]:font-semibold [&_strong]:tabular-nums [&_strong>span]:text-[16px]",
        "[&_strong>span]:tracking-0 [&_strong>span]:text-[#61708a] [&_strong>span]:font-[450] [&_p]:mt-[7px]",
        "[&_p]:mb-0 [&_p]:text-[#536176] [&_p]:text-[11px] [&_p]:leading-[1.5] [&_p]:whitespace-nowrap [&_p]:mx-0",
        "max-[1000px]:pl-[20px] max-[1000px]:gap-[12px] max-[760px]:order-2 max-[760px]:border-l-0",
        "max-[760px]:pt-[20px] max-[760px]:pr-0 max-[760px]:pb-0 max-[760px]:pl-[28px] max-[760px]:gap-[17px]",
        "max-[760px]:[&_p]:mt-[4px] max-[760px]:[&_p]:text-[12px] max-[760px]:[&_p]:whitespace-normal"
      ]}>
        <svg
          viewBox="0 0 64 64"
          aria-hidden="true"
          class={[
            "acceptance-ring w-[64px] h-[64px] flex-[0_0_64px] overflow-visible max-[1000px]:w-[50px]",
            "max-[1000px]:h-[50px] max-[1000px]:basis-[50px]"
          ]}
        >
          <circle cx="32" cy="32" r="27" class="ring-track" />
          <circle
            cx="32"
            cy="32"
            r="27"
            class="ring-progress"
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
    </.overview>
    <details
      data-ui="instructions"
      class={[
        "border border-panel rounded-[10px] bg-white [&_summary]:flex [&_summary]:justify-between",
        "[&_summary]:items-center [&_summary]:cursor-pointer [&_summary]:font-[550] [&_summary]:text-[13px]",
        "[&_summary]:list-none [&_summary]:bg-surface-heading [&_summary]:rounded-[9px] [&_summary]:py-[17px]",
        "[&_summary]:px-[20px] [&_summary]:gap-[16px] [&_summary::-webkit-details-marker]:hidden",
        "[&_summary:hover]:bg-surface-hover [&_summary:hover]:rounded-[8px] [&[open]_summary]:border-b",
        "[&[open]_summary]:border-b-line [&[open]_summary]:rounded-[9px_9px_0_0]",
        "[&[open]_summary>span]:[transform:rotate(180deg)]"
      ]}
      id={"instructions-#{@assignment.key}"}
    >
      <summary>
        <h2>{gettext("Assignment instructions")}</h2><.icon name="hero-chevron-down" class="size-4" />
      </summary>
      <div class={[
        "pt-[20px] pb-[24px] max-w-[760px] text-[#56647b] leading-[1.8] markdown px-[24px]",
        "[&_ol]:list-decimal [&_ol]:pl-[20px] [&_ol]:mb-[16px] max-[760px]:text-[13px] max-[760px]:p-[18px]"
      ]}>
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
    <.tabs
      id="assignment-sections"
      label={gettext("Assignment sections")}
      class="[&+[data-ui~=submissions]]:mt-[24px]"
    >
      <.tab
        patch={"/classrooms/#{@classroom.slug}/assignments/#{@assignment.key}"}
        active={@tab == "submissions"}
      >
        <.icon name="hero-inbox-arrow-down" class="size-4" />{gettext("Submissions")}
      </.tab>
      <.tab
        patch={"/classrooms/#{@classroom.slug}/assignments/#{@assignment.key}?view=tests"}
        active={@tab == "tests"}
        count={length(@tests)}
      >
        <.icon name="hero-beaker" class="size-4" />{gettext("Tests")}
      </.tab>
    </.tabs>
    <section
      :if={@tab == "submissions"}
      data-ui="submissions"
      aria-labelledby="assignment-submissions-title"
      class="mt-[36px] max-[760px]:mt-[28px]"
    >
      <div
        data-ui="submissions-heading"
        class={[
          "flex flex-wrap items-center justify-between mt-[24px] mb-[18px] gap-[10px] [&_h2]:text-[17px]",
          "[&_h2]:font-semibold [&>span]:text-muted [&>span]:text-[12px] [&>span]:hidden"
        ]}
      >
        <h2 id="assignment-submissions-title">
          {if @assignment.group?, do: gettext("Teams"), else: gettext("Students")}
        </h2><span>{gettext("%{accepted} of %{total} students have accepted",
          accepted: @accepted,
          total: @total
        )}</span>
        <div
          data-ui="submission-actions"
          class="ml-auto flex flex-wrap items-stretch justify-end gap-[10px] max-[600px]:w-full max-[600px]:[&>button]:flex-1"
        >
          <.button phx-click={JS.push_focus() |> JS.push("open", value: %{kind: "clone_all"})}><.icon
            name="hero-command-line"
            class="size-4"
          />{gettext("Clone all locally")}</.button>
          <.button
            :if={teacher_managed_teams?(@assignment, @preview)}
            phx-click={JS.push_focus() |> JS.push("open", value: %{kind: "teams"})}
          ><.icon name="hero-user-group" class="size-4" />{gettext("Manage teams")}</.button>
        </div>
      </div>
      <form
        id="submission-search"
        class="flex flex-wrap mb-[20px] gap-[12px] [&_.ui-search]:w-[320px] max-[760px]:flex-col max-[760px]:[&_.ui-search]:w-full"
        phx-change="filter_submissions"
        role="search"
      >
        <.search_input
          id="submission-query"
          label={gettext("Search by name or GitHub username")}
          name="query"
          placeholder={gettext("Search by name or GitHub username")}
          value={@query}
          phx-debounce="150"
        />
        <.field>
          <span class="sr-only">{gettext("Filter by progress")}</span><.input
            type="select"
            name="status"
          >
            <option
              value="all"
              selected={@filter == "all"}
            >
              {gettext("All progress")}
            </option><option
              :for={status <- [:pushed, :late, :no_push, :not_accepted]}
              :if={
                !@assignment.group? or Map.get(@assignment, :team_mode) == "teacher" or
                  status != :not_accepted
              }
              value={status}
              selected={@filter == to_string(status)}
            >
              {status_label(status)}
            </option>
          </.input>
        </.field>
      </form>
      <.data_list :if={@rows != []}>
        <.data_table kind="submissions">
          <caption class="sr-only">
            {gettext("Repositories and progress for this assignment")}
          </caption>
          <.list_header kind="table">
            <tr>
              <th scope="col">
                {if @assignment.group?, do: gettext("Team"), else: gettext("Student")}
              </th><th scope="col">
                {gettext("Last push")}
              </th><th scope="col">{gettext("Activity")}</th><th :if={@assignment.tests?} scope="col">
                {gettext("Test score")}
              </th><th scope="col" class="text-right">
                {gettext("Actions")}
              </th>
            </tr>
          </.list_header>
          <tbody>
            <tr :for={row <- @rows} id={"submission-#{row.key}"}>
              <th
                scope="row"
                class={[
                  "w-[32%] [&_strong]:block [&_strong]:font-[550] [&_strong]:mb-[4px] [&_strong]:text-[14px]",
                  "[&_strong]:tracking-[-.15px] [&>span]:block [&>span]:font-normal [&>span]:text-[11px] [&>span]:text-muted",
                  "[&>span]:wrap-anywhere max-[760px]:col-span-full max-[760px]:w-full max-[760px]:[&>span]:text-[12px]"
                ]}
              >
                <strong>{row.name}</strong>
                <span :if={Map.get(row, :deleted_team?, false)}>{gettext(
                  "Deleted team · results kept"
                )}</span>
                <span :if={!@assignment.group?}>
                  <a
                    href={"https://github.com/#{row.handle}"}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="underline-offset-[3px] hover:text-brand hover:underline"
                  >@{row.handle}</a>
                </span>
                <span
                  :if={@assignment.group? and row.member_profiles != []}
                  class="flex! items-start gap-[6px]"
                >
                  <.icon name="hero-user-group" class="mt-[2px] size-3.5 shrink-0" />
                  <span class="flex min-w-0 flex-wrap gap-y-[3px] gap-x-[10px]">
                    <a
                      :for={member <- row.member_profiles}
                      href={"https://github.com/#{member.handle}"}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="underline-offset-[3px] hover:text-brand hover:underline"
                    >{member.name}</a>
                  </span>
                </span>
                <span :if={@assignment.group? and row.member_profiles == []}>
                  {gettext("No students assigned yet.")}
                </span>
              </th>
              <td
                data-ui="push-cell"
                class={[
                  "text-muted whitespace-nowrap max-[760px]:before:[content:attr(data-label)] max-[760px]:before:block",
                  "max-[760px]:before:text-muted max-[760px]:before:text-[11px] max-[760px]:before:mb-[4px]",
                  "max-[760px]:col-start-1 max-[760px]:row-start-2 max-[760px]:whitespace-normal"
                ]}
                data-label={gettext("Last push")}
              >
                <span :if={row.pushed}>{local(row.pushed, @locale)}</span><.dash
                  :if={!row.pushed and not (@assignment.group? and row.status == :not_accepted)}
                  label={gettext("No pushes")}
                />
                <span
                  :if={@assignment.group? and row.status == :not_accepted}
                  class="whitespace-normal"
                >
                  {gettext("Waiting for acceptance")}
                </span>
                <span
                  :if={row.status == :late}
                  class="block text-warning text-[11px] mt-[3px]"
                >{gettext("Late")}</span>
              </td>
              <td
                class={[
                  "max-[760px]:col-span-full max-[760px]:before:[content:attr(data-label)] max-[760px]:before:block",
                  "max-[760px]:before:text-[11px] max-[760px]:before:text-muted max-[760px]:before:mb-[3px]"
                ]}
                data-label={gettext("Activity")}
              >
                <.activity
                  counts={row.activity}
                  dates={@dates}
                  max_count={@activity_max}
                  preview={@preview}
                />
              </td>
              <td
                :if={@assignment.tests?}
                class={[
                  "text-muted [&>span]:inline-flex [&>span]:items-center [&>span]:whitespace-nowrap [&>span]:gap-[5px]",
                  "max-[760px]:before:[content:attr(data-label)] max-[760px]:before:block max-[760px]:before:text-muted",
                  "max-[760px]:before:text-[11px] max-[760px]:before:mb-[4px] max-[760px]:col-start-2 max-[760px]:row-start-2"
                ]}
                data-label={gettext("Test score")}
              >
                <span
                  :if={row.score != nil}
                  data-ui="test-score"
                  class="text-[#35455c] tabular-nums font-semibold [&>span]:text-muted [&>span]:font-normal"
                >{Presentation.points(row.score)}<span> / {Presentation.points(@total_points)}</span></span>
                <span
                  :if={Map.get(row, :grade_untrusted?, false)}
                  class="block text-warning text-[11px] mt-[3px]"
                  title={gettext("The grading workflow changed. This result cannot be verified.")}
                >{gettext("Workflow changed")}</span>
                <.dash
                  :if={row.score == nil and not Map.get(row, :grade_untrusted?, false)}
                  label={gettext("Not run")}
                />
                <.button
                  :if={!@preview and Map.get(row, :subject_id)}
                  data-ui="results-link"
                  variant="link"
                  class="block! mt-[6px]"
                  phx-click={
                    JS.push_focus()
                    |> JS.push("open", value: %{kind: "test_results", subject_id: row.subject_id})
                  }
                  aria-label={gettext("View test results for %{name}", name: row.name)}
                >{gettext("View results")}</.button>
              </td>
              <td class={[
                "text-muted text-right [&_[data-ui~=field-help]]:mt-[6px] [&_[data-ui~=field-help]]:mb-0",
                "[&_[data-ui~=field-help]]:mx-0 max-[760px]:[&:not(:has(a,button,p))]:hidden! max-[760px]:col-span-full",
                "max-[760px]:border-t max-[760px]:border-t-[#eef1f5] max-[760px]:pt-[10px]!"
              ]}>
                <div class="flex justify-end items-center gap-[6px]">
                  <.button
                    :if={!@preview and row.repository_url}
                    size="small"
                    href={row.repository_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    aria-label={gettext("Open repository %{repository}", repository: row.repository)}
                  ><.icon name="hero-arrow-top-right-on-square" class="size-4" />{gettext(
                    "Repository"
                  )}</.button><.button
                    :if={@preview and row.repository}
                    type="submit"
                    size="small"
                    disabled
                    title={gettext("Repository links are unavailable in this preview.")}
                    aria-label={gettext("Open repository %{repository}", repository: row.repository)}
                  ><.icon name="hero-arrow-top-right-on-square" class="size-4" />{gettext(
                    "Repository"
                  )}</.button>
                  <.button
                    :if={
                      not @preview and not is_nil(Map.get(row, :subject_id)) and
                        not is_nil(@assignment.deadline_at)
                    }
                    variant="ghost"
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
                  ><.icon name="hero-calendar-days" class="size-4" /></.button>
                </div>
                <.field_hint :if={Map.get(row, :repository_state) == "pending"}>
                  {gettext("Repository is being created.")}
                </.field_hint>
                <.field_hint :if={Map.get(row, :access_sync_state) == "pending"}>
                  {gettext("Updating GitHub access…")}
                </.field_hint>
                <div :if={!@preview and Map.get(row, :access_sync_state) == "failed"} class="mt-[8px]">
                  <p class="mb-[6px] text-[12px] text-error">
                    {gettext("GitHub access could not be updated. Previous access may remain.")}
                  </p>
                  <.button
                    phx-click="retry_repository_access"
                    phx-value-subject_id={row.subject_id}
                    aria-label={gettext("Retry GitHub access update for %{name}", name: row.name)}
                  >
                    <.icon name="hero-arrow-path" class="size-4" />{gettext("Retry access update")}
                  </.button>
                </div>
                <div
                  :if={!@preview and Map.get(row, :repository_state) == "failed"}
                  class="[&_p]:mt-[3px] [&_p]:mb-[6px] [&_p]:text-error [&_p]:text-[12px] [&_p]:leading-[1.5] [&_p]:mx-0"
                >
                  <p>{Map.get(row, :repository_error)}</p>
                  <.button
                    phx-click="retry_repository"
                    phx-value-subject_id={row.subject_id}
                    aria-label={gettext("Retry repository setup for %{name}", name: row.name)}
                  ><.icon name="hero-arrow-path" class="size-4" />{gettext("Retry setup")}</.button>
                </div>
                <div
                  :if={Map.get(row, :extension_label)}
                  data-ui="deadline-extension"
                  class="ml-auto mt-[10px] flex w-fit max-w-[240px] items-start gap-[8px] rounded-[6px] bg-surface-heading px-[10px] py-[8px] text-left text-[12px] leading-[1.5]"
                >
                  <.icon name="hero-calendar-days" class="mt-[2px] size-4 shrink-0 text-muted" />
                  <div class="min-w-0">
                    <p class="font-semibold text-heading">{gettext("Extended deadline")}</p>
                    <p class="text-muted">{local(Map.get(row, :extension_label), @locale)}</p>
                  </div>
                </div>
              </td>
            </tr>
          </tbody>
        </.data_table>
      </.data_list>
      <.empty_state :if={@rows == []}>
        <.icon name="hero-user-group" class="size-8" /><h3>
          {cond do
            @query != "" or @filter != "all" -> gettext("No matching results")
            @total == 0 -> gettext("No students yet")
            @assignment.group? and @assignment.submitted == 0 -> gettext("No teams yet")
            true -> gettext("No matching results")
          end}
        </h3><p>
          {cond do
            @query != "" or @filter != "all" -> gettext("Try another search or progress filter.")
            @total == 0 -> gettext("Share the classroom link to let your students join.")
            true -> empty_message(@assignment, @teams)
          end}
        </p>
      </.empty_state>
      <p :if={@assignment.group?} class="text-muted text-[12px] mt-[18px]">
        {gettext("One shared repository per team.")}
      </p>
      <p :if={@preview} class="text-muted text-[12px] mt-[16px] mb-0 mx-0">
        {gettext("Repository links are unavailable in this preview.")}
      </p>
    </section>
    <section
      :if={@tab == "tests"}
      class="mt-[28px]"
      aria-labelledby="test-catalog-title"
    >
      <div
        data-ui="submissions-heading"
        class={[
          "flex flex-wrap items-center justify-between mt-[24px] mb-[18px] gap-[10px] [&_h2]:text-[17px]",
          "[&_h2]:font-semibold [&>span]:text-muted [&>span]:text-[12px] [&>span]:hidden"
        ]}
      >
        <h2 id="test-catalog-title">{gettext("Automatic tests")}</h2>
        <span :if={@tests != []}>
          {gettext("%{points} points total", points: @total_points)}
        </span>
      </div>
      <.lead :if={@tests != []}>
        {gettext(
          "These tests run in GitHub Actions on each push. The score is the sum of the points earned."
        )}
      </.lead>
      <ol
        :if={@tests != []}
        data-ui="test-list"
        class={[
          "bg-white list-none border border-line rounded-[9px] overflow-hidden p-0 my-[24px] mx-0 [&_li]:flex",
          "[&_li]:items-start [&_li]:justify-between [&_li]:border-t [&_li]:border-t-line [&_li]:p-[23px]",
          "[&_li]:gap-[24px] [&_li:first-child]:border-t-0 [&_h3]:text-[14px] [&_h3]:font-semibold [&_p]:text-muted",
          "[&_p]:text-[13px] [&_p]:leading-[1.65] [&_p]:mt-[6px] [&_li>span]:whitespace-nowrap [&_li>span]:text-[13px]",
          "[&_li>span]:text-[#4e6079] [&_li>span]:tabular-nums max-[760px]:[&_li]:p-[18px]",
          "max-[760px]:[&_li]:gap-[12px]"
        ]}
      >
        <li :for={test <- @tests}>
          <div>
            <h3>{test.name}</h3><p :if={test.description not in [nil, ""]}>
              {test.description}
            </p>
            <code
              :if={test[:type]}
              data-ui="test-command"
              class="block text-[12px] wrap-anywhere mt-[12px]"
            >{if test.type ==
                   "file",
                 do: test.path,
                 else: test.command}</code>
            <div
              :if={test[:type] == "io"}
              class={[
                "[&_pre]:overflow-auto [&_pre]:bg-[#f5f7fa] [&_pre]:rounded-[6px] [&_pre]:text-[12px] [&_pre]:p-[12px]",
                "[&_pre]:my-[12px] [&_pre]:mx-0"
              ]}
            >
              <p>{gettext("Standard input (optional)")}</p><pre>{test.input || ""}</pre><p>
                {gettext("Expected output")}
              </p><pre>{test.expected}</pre>
            </div>
          </div><span>{gettext("%{points} points", points: test.points)}</span>
        </li>
      </ol>
      <.empty_state :if={@tests == []}>
        <.icon name="hero-beaker" class="size-8" /><h3>{gettext("No automatic tests")}</h3><p>
          {gettext("This assignment has no automatic test score.")}
        </p>
      </.empty_state>
    </section>
    """
  end

  attr :label, :string, required: true

  defp dash(assigns) do
    ~H"""
    <span data-ui="dash" class="text-muted">
      <span aria-hidden="true">—</span><span class="sr-only">{@label}</span>
    </span>
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
      class="sparkline"
      viewBox="0 0 110 34"
      role="img"
      tabindex="0"
      aria-label={@summary}
    ><title>{@summary}</title><path d="M3 30H107" class="sparkline-base" /><polyline points={@points} /><circle
      :for={sample <- @samples}
      :if={sample.count > 0}
      cx={sample.x}
      cy={sample.y}
      r="2"
    >
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
