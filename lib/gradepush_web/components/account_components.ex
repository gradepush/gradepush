defmodule GradePushWeb.AccountComponents do
  @moduledoc false
  use GradePushWeb, :html

  attr :user, :map, required: true
  attr :organizations, :list, required: true
  attr :section, :string, required: true
  attr :preview, :boolean, default: false
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
        <.settings_feedback notice={@notice} error={@error} />
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
        <.settings_feedback notice={@notice} error={@error} />
        <div>
          <div :if={@organizations == []} class="p-[22px] max-[760px]:p-[18px]">
            <.notice
              kind="error"
              icon="hero-exclamation-circle"
              class="!mb-0 text-[13px] leading-[1.6]"
            >
              {gettext("Connect a GitHub organization before creating a classroom.")}
            </.notice>
          </div>
          <div
            :for={organization <- @organizations}
            data-ui="organization-row"
            class="border-t border-line p-[22px] first:border-t-0 max-[760px]:p-[18px]"
          >
            <div class="flex flex-wrap items-center gap-[14px]">
              <span class="flex size-[36px] shrink-0 items-center justify-center rounded-[7px] bg-neutral-hover text-muted">
                <.icon name="hero-building-office-2" class="size-5" />
              </span>
              <div class="min-w-0 flex-1 basis-[140px]">
                <strong class="break-words">{organization_name(organization)}</strong>
                <p class="mt-[4px] text-[12px] text-muted break-words">
                  {gettext("Connected as @%{username}", username: @user.handle)}
                </p>
              </div>
              <.connection_status :if={connection_active?(organization)} class="!ml-0">
                {gettext("Connected")}
              </.connection_status>
              <span :if={!connection_active?(organization)} class="text-[12px] text-danger">
                {gettext("Connection unavailable")}
              </span>
              <.button
                :if={is_map(organization)}
                phx-click="check_organization"
                phx-value-id={organization.id}
                phx-disable-with={gettext("Checking…")}
                size="small"
                class="ml-auto"
              >
                <.icon name="hero-arrow-path" class="size-4" />{gettext("Check connection")}
              </.button>
            </div>
          </div>
          <div
            data-ui="settings-actions"
            class="flex flex-wrap items-center gap-[16px] border-t border-line px-[22px] py-[16px] max-[760px]:px-[18px]"
          >
            <.button
              href={if !@preview && !GradePush.Demo.enabled?(), do: ~p"/github/organizations/connect"}
              disabled={@preview || GradePush.Demo.enabled?()}
            >
              <.icon name="hero-plus" class="size-4" />{gettext("Connect an organization")}
            </.button>
            <.button
              variant="text"
              phx-click={JS.push_focus() |> JS.push("open", value: %{kind: "connect_organization"})}
            >
              {gettext("Already installed on GitHub?")}
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

  defp connection_active?(%{status: status}), do: status == "active"
  defp connection_active?(_), do: true

  defp organization_name(%{login: login}), do: login
  defp organization_name(name), do: name

  attr :notice, :string, default: nil
  attr :error, :string, default: nil

  defp settings_feedback(assigns) do
    ~H"""
    <div
      :if={@notice || @error}
      data-ui="settings-feedback"
      class="px-[22px] pt-[16px] max-[760px]:px-[18px]"
    >
      <.notice :if={@error} kind="error" role="alert" class="!m-0">{@error}</.notice>
      <.notice :if={@notice} kind="success" role="status" class="!m-0">{@notice}</.notice>
    </div>
    """
  end

  def organization_error(:organization_owner_required),
    do: gettext("You must be an owner of this GitHub organization to connect it.")

  def organization_error(:invalid_state),
    do:
      gettext(
        "This connection request has expired. Click ‘Connect an organization’ to try again."
      )

  def organization_error(:github_reauthorization_required),
    do: gettext("Sign out and sign in with GitHub again, then retry connecting the organization.")

  def organization_error(_),
    do:
      gettext(
        "Could not connect this organization. Choose an organization instead of a personal account and check your GitHub permissions."
      )
end
