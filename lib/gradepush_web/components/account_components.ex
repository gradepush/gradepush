defmodule GradePushWeb.AccountComponents do
  @moduledoc false
  use GradePushWeb, :html

  attr :user, :map, required: true
  attr :organizations, :list, required: true
  attr :section, :string, required: true
  attr :sharing_teachers, :list, default: []
  attr :notice, :string, default: nil
  attr :error, :string, default: nil

  def settings(assigns) do
    ~H"""
    <.page_heading>
      <div>
        <h1>{gettext("Settings")}</h1><.lead>
          {gettext("Your GitHub account and the organizations you teach with.")}
        </.lead>
      </div>
    </.page_heading>
    <div class={[
      "grid grid-cols-[220px_minmax(0,1fr)] [align-items:start] gap-[32px] [&>[data-ui~=error]]:col-span-full",
      "[&>[data-ui~=error]]:m-0 [&>[data-ui~=notice]]:col-span-full [&>[data-ui~=notice]]:m-0",
      "max-[760px]:grid-cols-[minmax(0,1fr)] max-[760px]:gap-[20px]"
    ]}>
      <.notice
        :if={@error}
        kind="error"
        role="alert"
      >
        {@error}
      </.notice>
      <.notice
        :if={@notice}
        kind="success"
        role="status"
      >
        {@notice}
      </.notice>
      <nav
        data-ui="settings-nav"
        class={[
          "grid gap-[6px] [&_a]:flex [&_a]:items-center [&_a]:min-h-[46px] [&_a]:rounded-[7px] [&_a]:text-muted",
          "[&_a]:text-[13px] [&_a]:font-[550] [&_a]:py-[12px] [&_a]:px-[14px] [&_a]:gap-[10px] [&_a:hover]:bg-selected",
          "[&_a:hover]:text-body [&_a[aria-current]]:bg-selected [&_a[aria-current]]:text-body [&_a>span]:shrink-0",
          "max-[760px]:grid-cols-[repeat(2,minmax(0,1fr))] max-[760px]:[&_a]:py-[12px] max-[760px]:[&_a]:px-[10px]",
          "max-[760px]:[&_a]:gap-[8px]"
        ]}
        aria-label={gettext("Account settings")}
      >
        <.link patch="/teacher/settings" aria-current={if @section == "account", do: "page"}>
          <.icon name="hero-user-circle" class="size-5" />{gettext("GitHub account")}
        </.link>
        <.link
          patch="/teacher/settings?section=organizations"
          aria-current={if @section == "organizations", do: "page"}
        >
          <.icon name="hero-building-office-2" class="size-5" />{gettext("Organizations")}
        </.link>
      </nav>
      <.panel
        :if={@section == "account"}
        variant="account"
        aria-labelledby="github-account-title"
      >
        <.panel_heading variant="account">
          <h2 id="github-account-title">{gettext("GitHub account")}</h2>
        </.panel_heading>
        <div class={[
          "flex items-center p-[22px] gap-[14px] [&>div]:min-w-0 [&_a]:flex [&_a]:items-center [&_a]:mt-[4px]",
          "[&_a]:text-muted [&_a]:text-[12px] [&_a]:gap-[4px] [&_a:hover]:text-brand [&_a:hover]:underline",
          "max-[760px]:flex-wrap max-[760px]:p-[18px]"
        ]}>
          <.user_avatar src={Map.get(@user, :avatar_url)} aria-hidden="true">
            {@user.initials}
          </.user_avatar>
          <div>
            <strong>{@user.name}</strong><a
              href={"https://github.com/#{@user.handle}"}
              target="_blank"
              rel="noopener noreferrer"
            >@{@user.handle}<.icon name="hero-arrow-up-right" class="size-3" /></a>
          </div>
          <.connection_status>{gettext("Connected")}</.connection_status>
        </div>
      </.panel>
      <.panel
        :if={@section == "organizations"}
        variant="account"
        aria-labelledby="github-organizations-title"
      >
        <.panel_heading variant="account">
          <h2 id="github-organizations-title">{gettext("GitHub organizations")}</h2>
          <p>{gettext("Choose a connected organization when creating a classroom.")}</p>
        </.panel_heading>
        <div>
          <p
            :if={@organizations == []}
            class="text-muted text-[13px] leading-[1.6] py-[20px] px-[22px] m-0 max-[760px]:p-[18px]"
          >
            {gettext("Connect a GitHub organization before creating a classroom.")}
          </p>
          <div
            :for={organization <- @organizations}
            data-ui="organization-row"
            class={[
              "flex items-center p-[22px] gap-[14px] [&>div]:min-w-0 [&>div>span]:flex [&>div>span]:items-center",
              "[&>div>span]:mt-[4px] [&>div>span]:text-muted [&>div>span]:text-[12px] [&>div>span]:gap-[4px]",
              "max-[760px]:flex-wrap max-[760px]:p-[18px]"
            ]}
          >
            <span class="flex items-center justify-center w-[36px] h-[36px] shrink-0 bg-neutral-hover rounded-[7px] text-muted"><.icon
              name="hero-building-office-2"
              class="size-5"
            /></span>
            <div>
              <strong>{organization_name(organization)}</strong>
              <span>{sharing_description(organization, Map.get(@user, :id))}</span>
            </div>
            <.connection_status>{gettext("Connected")}</.connection_status>
            <form
              :if={
                shareable?(organization, Map.get(@user, :id)) and
                  shareable_teachers(organization, @sharing_teachers) != []
              }
              phx-submit="share_organization"
              class={[
                "flex flex-[0_0_100%] items-center ml-[50px] gap-[8px] [&_label]:min-w-[220px] max-[760px]:ml-0",
                "max-[760px]:flex-wrap max-[760px]:[&_label]:flex-[1_1_180px]"
              ]}
            >
              <.input type="hidden" name="connection_id" value={organization.id} />
              <.field>
                <span class="sr-only">{gettext("Choose a teacher to share with")}</span>
                <.input type="select" name="teacher_id" required>
                  <option value="">{gettext("Share with a teacher")}</option>
                  <option
                    :for={teacher <- shareable_teachers(organization, @sharing_teachers)}
                    value={teacher.id}
                  >
                    {teacher.name}
                  </option>
                </.input>
              </.field>
              <.button type="submit">{gettext("Share")}</.button>
            </form>
          </div>
          <div
            data-ui="settings-actions"
            class="border-t border-t-line py-[16px] px-[22px] max-[760px]:py-[16px] max-[760px]:px-[18px]"
          >
            <.button phx-click={
              JS.push_focus() |> JS.push("open", value: %{kind: "connect_organization"})
            }>
              <.icon name="hero-plus" class="size-4" />{gettext("Connect an organization")}
            </.button>
          </div>
        </div>
      </.panel>
    </div>
    """
  end

  def signed_out(assigns) do
    assigns = assign_new(assigns, :preview, fn -> true end)

    ~H"""
    <section
      data-ui="sign-in"
      class={[
        "max-w-[460px] text-center bg-white border border-subtle rounded-[12px] py-[36px] px-[28px] my-[48px] mx-auto",
        "[&_h1]:text-[28px] [&_h1]:font-semibold [&_h1]:mt-[20px] [&_h1]:mb-[12px] [&_h1]:mx-0 [&_p]:text-muted",
        "[&_p]:leading-[1.65] [&_[data-variant=primary]]:mt-[24px] max-[760px]:py-[28px] max-[760px]:px-[20px]",
        "max-[760px]:my-[24px] max-[760px]:mx-auto"
      ]}
    >
      <span class="inline-flex rounded-full bg-[#eef2ff] text-brand p-[12px]"><.icon
        name="hero-academic-cap"
        class="size-8"
      /></span>
      <h1>{gettext("See you soon")}</h1>
      <p>{gettext("Sign in with GitHub to return to your classrooms.")}</p>
      <.button :if={@preview} patch="/classrooms" variant="primary">{gettext("Sign in with GitHub")}<.icon
        name="hero-arrow-right"
        class="size-4"
      /></.button>
      <.button :if={!@preview} href="/auth/github" variant="primary">{gettext("Sign in with GitHub")}<.icon
        name="hero-arrow-right"
        class="size-4"
      /></.button>
      <p :if={@preview} class="text-muted text-[12px] mt-[16px] mb-0 mx-0">
        {gettext("Sign-in and sign-out are simulated in this preview.")}
      </p>
    </section>
    """
  end

  defp organization_name(%{login: login}), do: login
  defp organization_name(name), do: name

  defp shareable?(organization, user_id) when is_map(organization),
    do: organization.sharing_scope == "private" and organization.connected_by_id == user_id

  defp shareable?(_, _), do: false

  defp sharing_description(%{sharing_scope: "institution"}, _user_id),
    do: gettext("Available to all institution teachers")

  defp sharing_description(organization, user_id) when is_map(organization) do
    cond do
      organization.connected_by_id != user_id -> gettext("Shared with you")
      organization.authorized_teachers != [] -> gettext("Shared with selected teachers")
      true -> gettext("Only available to you")
    end
  end

  defp sharing_description(_, _), do: gettext("Only available to you")

  defp shareable_teachers(organization, teachers) do
    existing_ids = Enum.map(organization.authorized_teachers, & &1.user_id)
    Enum.reject(teachers, &(&1.id in existing_ids))
  end
end
