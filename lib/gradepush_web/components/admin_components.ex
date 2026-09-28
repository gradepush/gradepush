defmodule GradePushWeb.AdminComponents do
  @moduledoc false
  use GradePushWeb, :html

  attr :events, :list, required: true

  def history(assigns) do
    ~H"""
    <div class={[
      "flex justify-between items-start mb-[20px] gap-[20px] [&_h2]:text-[16px] [&_h2]:font-semibold",
      "[&_p]:text-[13px] [&_p]:text-muted [&_p]:mt-[6px] [&_p]:leading-[1.6]"
    ]}>
      <div>
        <h2>{gettext("Administrative history")}</h2><p>{gettext("Who changed what, and when.")}</p>
      </div><.badge>{gettext("Read only")}</.badge>
    </div>
    <.empty_state :if={@events == []}>
      <.icon name="hero-clock" class="size-8" /><h3>{gettext("No administrative changes yet")}</h3>
    </.empty_state>
    <ol
      :if={@events != []}
      data-ui="audit-list"
      class={[
        "bg-white border border-panel rounded-[12px] shadow-panel [&_li]:flex [&_li]:items-start [&_li]:border-b",
        "[&_li]:border-b-line [&_li]:p-[22px] [&_li]:gap-[16px] [&_li:last-child]:border-b-0 [&_strong]:text-[13px]",
        "[&_strong]:font-[550] [&_p]:text-muted [&_p]:text-[13px] [&_p]:mt-[5px] [&_li>div>span]:block",
        "[&_li>div>span]:text-muted [&_li>div>span]:text-[12px] [&_li>div>span]:mt-[8px] [&_time]:ml-auto",
        "[&_time]:text-[12px] [&_time]:text-muted [&_time]:whitespace-nowrap max-[760px]:[&_li]:flex-wrap",
        "max-[760px]:[&_li]:p-[18px] max-[760px]:[&_li>div]:flex-1 max-[760px]:[&_li>div]:min-w-0",
        "max-[760px]:[&_time]:ml-[46px] max-[760px]:[&_time]:w-full"
      ]}
    >
      <li :for={event <- @events}>
        <span class="w-[30px] h-[30px] border border-line rounded-full flex justify-center items-center text-muted shrink-0"><.icon
          name="hero-clock"
          class="size-4"
        /></span>
        <div>
          <strong>{event.action}</strong><p>{event.target}</p><span>{event.actor}</span>
        </div>
        <time>{event.time}</time>
      </li>
    </ol>
    """
  end

  attr :directory, :map, required: true
  attr :actor_id, :string, required: true

  def student_directory(assigns) do
    ~H"""
    <.list_toolbar class="max-[760px]:justify-start!">
      <div>
        <h2>{gettext("Registered students")}</h2>
        <p class="mt-[6px] text-[13px] text-muted">
          {ngettext("%{count} student", "%{count} students", @directory.total)}
        </p>
      </div>
      <form
        id="student-directory-search"
        phx-change="search_students"
        phx-submit="search_students"
        role="search"
      >
        <.search_input
          id="student-directory-query"
          name="query"
          value={@directory.query}
          label={gettext("Search students")}
          placeholder={gettext("Name, student ID or GitHub username")}
          maxlength="100"
          phx-debounce="250"
        />
      </form>
    </.list_toolbar>
    <.data_list :if={@directory.entries != []}>
      <.data_table kind="admin">
        <caption class="sr-only">{gettext("Registered students")}</caption>
        <.list_header kind="table">
          <tr>
            <th scope="col">{gettext("Student")}</th><th scope="col">{gettext("Student ID")}</th><th scope="col">
              {gettext("GitHub account")}
            </th><th scope="col">{gettext("Classrooms")}</th>
            <th scope="col"><span class="sr-only">{gettext("Actions")}</span></th>
          </tr>
        </.list_header>
        <tbody>
          <tr :for={student <- @directory.entries} id={"institution-student-#{student.id}"}>
            <th scope="row">
              <div class="flex items-center gap-[12px]">
                <.user_avatar src={student.avatar_url} size="small">
                  {GradePushWeb.Presentation.initials(student.name)}
                </.user_avatar>
                <strong class="min-w-0 break-words">{student.name}</strong>
              </div>
            </th>
            <td data-label={gettext("Student ID")}>{student.identifier}</td>
            <td data-label={gettext("GitHub account")}>
              <a
                href={"https://github.com/#{student.handle}"}
                target="_blank"
                rel="noopener noreferrer"
                class="inline-flex items-center gap-[4px] text-brand hover:underline break-all"
              >@{student.handle}<.icon name="hero-arrow-up-right" class="size-3 shrink-0" /></a>
            </td>
            <td data-label={gettext("Classrooms")}>{student.classrooms}</td>
            <td class="text-right max-[760px]:col-span-full">
              <.button
                variant="text-danger"
                size="compact"
                phx-click={
                  JS.push_focus() |> JS.push("open_student_removal", value: %{id: student.id})
                }
                disabled={to_string(student.id) == @actor_id}
                aria-label={gettext("Remove %{name} from the institution", name: student.name)}
              >{gettext("Remove")}</.button>
            </td>
          </tr>
        </tbody>
      </.data_table>
    </.data_list>
    <.empty_state :if={@directory.entries == []}>
      <.icon name="hero-academic-cap" class="size-8" />
      <h2>
        {if @directory.query == "",
          do: gettext("No registered students yet"),
          else: gettext("No matching students")}
      </h2>
      <p>
        {if @directory.query == "",
          do: gettext("Students appear here once they have completed their name and student ID."),
          else: gettext("Try another name, student ID or GitHub username.")}
      </p>
    </.empty_state>
    <nav
      :if={@directory.pages > 1}
      aria-label={gettext("Student pages")}
      class="mt-[20px] flex flex-wrap items-center justify-between gap-[12px]"
    >
      <p class="text-[13px] text-muted">
        {gettext("Page %{page} of %{pages}", page: @directory.page, pages: @directory.pages)}
      </p>
      <div class="flex gap-[10px]">
        <.button
          phx-click="student_page"
          phx-value-page={@directory.page - 1}
          disabled={@directory.page == 1}
        >{gettext("Previous")}</.button>
        <.button
          phx-click="student_page"
          phx-value-page={@directory.page + 1}
          disabled={@directory.page == @directory.pages}
        >{gettext("Next")}</.button>
      </div>
    </nav>
    """
  end

  attr :users, :list, required: true
  attr :actor_id, :string, required: true
  attr :preview, :boolean, default: false

  def platform_administrators(assigns) do
    ~H"""
    <.list_toolbar>
      <div>
        <h2>{gettext("Platform administrators")}</h2>
        <p class="mt-[6px] text-[13px] text-muted">
          {gettext("Platform access is separate from institution administration.")}
        </p>
      </div>
      <.button phx-click="add_platform_admin" variant="primary" disabled={@preview}>
        <.icon name="hero-plus" class="size-4" />{gettext("Add an administrator")}
      </.button>
    </.list_toolbar>
    <.data_list>
      <.data_table kind="admin">
        <caption class="sr-only">{gettext("Platform administrators")}</caption>
        <.list_header kind="table">
          <tr>
            <th scope="col">{gettext("Administrator")}</th><th scope="col" class="text-right">
              <span class="sr-only">{gettext("Actions")}</span>
            </th>
          </tr>
        </.list_header>
        <tbody>
          <tr :for={user <- @users} id={"platform-admin-#{user.id}"}>
            <td data-label={gettext("Administrator")}>
              <div class="flex items-center gap-[12px]">
                <.user_avatar src={user.avatar_url}>{user.initials}</.user_avatar>
                <div class="min-w-0">
                  <strong class="break-words">{user.name}</strong><.badge
                    :if={to_string(user.id) == @actor_id}
                    class="ml-[8px]"
                  >
                    {gettext("You")}
                  </.badge><p class="text-[12px] text-muted break-words">@{user.handle}</p>
                </div>
              </div>
            </td>
            <td class="text-right max-[760px]:col-span-full">
              <.button
                variant="text-danger"
                phx-click="remove_platform_admin"
                phx-value-id={user.id}
                disabled={@preview or length(@users) == 1}
                aria-label={gettext("Remove platform access for %{name}", name: user.name)}
              >{gettext("Remove access")}</.button>
            </td>
          </tr>
        </tbody>
      </.data_table>
    </.data_list>
    <p class="mt-[16px] text-[13px] text-muted">
      {gettext(
        "Keep at least one platform administrator. Add another administrator before removing this access."
      )}
    </p>
    """
  end

  attr :section, :string, required: true
  attr :platform, :map, required: true

  def platform(assigns) do
    ~H"""
    <%= case @section do %>
      <% "configuration" -> %>
        <.panel>
          <.panel_heading>
            <.icon name="hero-server-stack" class="size-5" /><div>
              <h2>{gettext("Instance configuration")}</h2><p>
                {gettext("Connection details for this GradePush installation.")}
              </p>
            </div><.badge :if={Map.get(@platform, :preview?, true)}>{gettext("Example")}</.badge>
          </.panel_heading>
          <dl
            data-ui="admin-properties"
            class={[
              "py-[4px] px-[22px] [&>div]:grid [&>div]:grid-cols-[210px_minmax(0,1fr)] [&>div]:border-b",
              "[&>div]:border-b-line [&>div]:text-[13px] [&>div]:py-[16px] [&>div]:px-0 [&>div]:gap-[24px]",
              "[&>div:last-child]:border-b-0 [&_dt]:text-muted [&_dd]:wrap-anywhere max-[760px]:py-[4px]",
              "max-[760px]:px-[18px] max-[760px]:[&>div]:grid-cols-[minmax(0,1fr)] max-[760px]:[&>div]:gap-[5px]"
            ]}
          >
            <div>
              <dt>{gettext("Public address")}</dt><dd>{@platform.public_address}</dd>
            </div>
            <div>
              <dt>{gettext("Time zone")}</dt><dd>{@platform.timezone}</dd>
            </div>
            <div>
              <dt>{gettext("GitHub App")}</dt><dd>{@platform.github_app}</dd>
            </div>
            <div>
              <dt>{gettext("Webhook address")}</dt><dd>{@platform.webhook_address}</dd>
            </div>
          </dl>
          <p class="border-t border-t-line text-muted text-[12px] py-[16px] px-[22px]">
            {gettext("Server configuration is managed by the installation operator.")}
          </p>
        </.panel>
      <% "services" -> %>
        <div class={[
          "flex justify-between items-start mb-[20px] gap-[20px] [&_h2]:text-[16px] [&_h2]:font-semibold",
          "[&_p]:text-[13px] [&_p]:text-muted [&_p]:mt-[6px] [&_p]:leading-[1.6]"
        ]}>
          <div>
            <h2>{gettext("Service status")}</h2><p>
              {gettext("Application connections and background work.")}
            </p>
          </div><.badge :if={Map.get(@platform, :preview?, true)}>
            {gettext("Simulated status")}
          </.badge>
        </div>
        <div data-ui="service-list" class="bg-white border border-panel rounded-[12px] shadow-panel">
          <.service
            icon="hero-circle-stack"
            name="PostgreSQL"
            detail={@platform.database_status}
            preview={Map.get(@platform, :preview?, true)}
          />
          <.service
            icon="hero-code-bracket"
            name="GitHub App"
            detail={@platform.app_status}
            preview={Map.get(@platform, :preview?, true)}
          />
          <.service
            icon="hero-arrow-path"
            name="Oban"
            detail={@platform.jobs_status}
            preview={Map.get(@platform, :preview?, true)}
          />
          <.service
            icon="hero-bolt"
            name="Webhooks"
            detail={@platform.webhook_status}
            preview={Map.get(@platform, :preview?, true)}
          />
        </div>
      <% "history" -> %>
        <.history events={@platform.history} />
    <% end %>
    """
  end

  attr :icon, :string, required: true
  attr :name, :string, required: true
  attr :detail, :string, required: true
  attr :preview, :boolean, default: true

  defp service(assigns) do
    ~H"""
    <div class={[
      "flex items-center border-b border-b-line p-[22px] gap-[14px] [&:last-child]:border-b-0 [&_h3]:text-[14px]",
      "[&_h3]:font-[550] [&_p]:text-muted [&_p]:text-[12px] [&_p]:mt-[4px]",
      "[&_[data-ui~=connection-state]>span]:w-[16px] [&_[data-ui~=connection-state]>span]:h-[16px]",
      "[&_[data-ui~=connection-state]>span]:bg-current max-[760px]:flex-wrap max-[760px]:p-[18px]",
      "max-[760px]:[&>div]:flex-1"
    ]}>
      <span class="flex items-center justify-center w-[36px] h-[36px] shrink-0 bg-neutral-hover rounded-[7px] text-muted"><.icon
        name={@icon}
        class="size-5"
      /></span><div>
        <h3>{@name}</h3><p>{@detail}</p>
      </div><.connection_status :if={@preview} icon="hero-check-circle">
        {gettext("Available")}
      </.connection_status>
    </div>
    """
  end
end
