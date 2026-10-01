defmodule GradePushWeb.WorkspaceLayout do
  @moduledoc false
  use GradePushWeb, :html

  attr :locale, :string, required: true
  attr :path, :string, required: true

  def public_header(assigns) do
    assigns = assign(assigns, :target_locale, if(assigns.locale == "fr", do: "en", else: "fr"))

    ~H"""
    <.header_frame>
      <a href="/" class="inline-flex items-center shrink-0 [&_img]:w-[140px] [&_img]:h-auto"><img
        src="/images/logo.svg"
        width="140"
        alt="GradePush"
      /></a>
      <div class="ml-auto flex items-center gap-[12px] max-[760px]:gap-[6px] max-[760px]:group-data-[context=true]/header:order-1">
        <.link
          data-ui="language"
          href={
            @path
            |> URI.parse()
            |> URI.append_query(URI.encode_query(%{locale: @target_locale}))
            |> URI.to_string()
          }
          lang={@target_locale}
          class={[
            "flex items-center justify-center min-h-[44px] rounded-[7px] text-muted text-[12px] font-semibold p-[8px]",
            "gap-[7px] hover:text-body"
          ]}
          aria-label={if @target_locale == "en", do: "Switch to English", else: "Passer en français"}
        >
          <.icon name="hero-globe-alt" class="size-4" />{String.upcase(@target_locale)}
        </.link>
      </div>
    </.header_frame>
    """
  end

  attr :user, :map, required: true
  attr :institution, :string, required: true
  attr :action, :atom, required: true
  attr :locale, :string, required: true
  attr :language_urls, :map, required: true
  attr :context, :atom, default: :teaching
  attr :contexts, :list, default: [:teaching]
  attr :preview, :boolean, default: true

  def header(assigns) do
    assigns = assign(assigns, :target_locale, if(assigns.locale == "fr", do: "en", else: "fr"))

    assigns =
      assign(
        assigns,
        :show_settings,
        :teaching in assigns.contexts and assigns.context != :learning
      )

    ~H"""
    <.header_frame context={@action != :signed_out and length(@contexts) > 1}>
      <.link
        {workspace_link(@context, "/classrooms")}
        class="inline-flex items-center shrink-0 [&_img]:w-[140px] [&_img]:h-auto"
      >
        <img src={~p"/images/logo.svg"} width="140" alt="GradePush" />
      </.link>
      <.dropdown
        :if={@action != :signed_out and length(@contexts) > 1}
        id="context-menu"
        kind="context"
        label={gettext("Switch workspace")}
      >
        <:trigger>
          <.icon name={context_icon(@context)} class="size-4" /><span>{context_label(@context)}</span>
        </:trigger>
        <.dropdown_link
          :for={context <- @contexts}
          {context_link(@context, context)}
          aria-current={if context == @context, do: "true"}
        >
          <.icon name={context_icon(context)} class="size-4" />
          {context_label(context)}
          <.icon
            :if={context == @context}
            name="hero-check"
            class="size-4 ml-auto text-brand"
          />
        </.dropdown_link>
      </.dropdown>
      <.main_navigation :if={@action != :signed_out and @context == :teaching}>
        <.link patch="/classrooms" aria-current={if @action != :settings, do: "page"}>
          <.icon name="hero-rectangle-stack" class="size-4" />{gettext("Classrooms")}
        </.link>
        <.link patch="/teacher/settings" aria-current={if @action == :settings, do: "page"}>
          <.icon name="hero-cog-6-tooth" class="size-4" />{gettext("Settings")}
        </.link>
      </.main_navigation>
      <.main_navigation :if={@context == :learning}>
        <.link navigate="/student/classrooms" aria-current={if @action != :schedule, do: "page"}>
          <.icon name="hero-rectangle-stack" class="size-4" />{gettext("Classrooms")}
        </.link>
        <.link navigate="/student/assignments" aria-current={if @action == :schedule, do: "page"}>
          <.icon name="hero-calendar-days" class="size-4" />{gettext("Assignments")}
        </.link>
      </.main_navigation>
      <div class="ml-auto flex items-center gap-[12px] max-[760px]:gap-[6px] max-[760px]:group-data-[context=true]/header:order-1">
        <.link
          data-ui="language"
          href={Map.fetch!(@language_urls, @target_locale)}
          lang={@target_locale}
          class={[
            "flex items-center justify-center min-h-[44px] rounded-[7px] text-muted text-[12px] font-semibold p-[8px]",
            "gap-[7px] hover:text-body"
          ]}
          aria-label={if @target_locale == "en", do: "Switch to English", else: "Passer en français"}
        >
          <.icon name="hero-globe-alt" class="size-4" />{String.upcase(@target_locale)}
        </.link>
        <.dropdown :if={@action != :signed_out} id="profile-menu" label={gettext("Account menu")}>
          <:trigger><.avatar user={@user} /></:trigger>
          <div
            data-ui="profile-identity"
            class={[
              "flex items-center pt-[12px] pb-[16px] px-[10px] gap-[12px] [&>div]:grid [&>div]:min-w-0",
              "[&>div]:wrap-anywhere [&>div]:gap-[3px] [&_strong]:text-[14px] [&_strong]:font-semibold",
              "[&>div>span]:text-muted [&>div>span]:text-[12px]"
            ]}
          >
            <.avatar user={@user} />
            <div><strong>{@user.name}</strong><span>@{@user.handle}</span></div>
          </div>
          <div
            data-ui={if @show_settings, do: "profile-divider"}
            class={[
              "flex items-center pt-0 pb-[16px] text-muted text-[12px] wrap-anywhere px-[10px] gap-[8px] [&>.size-4]:shrink-0",
              @show_settings &&
                "mb-[6px] border-b border-b-line"
            ]}
          >
            <.icon name="hero-building-library" class="size-4" />
            <span>{@institution}</span>
          </div>
          <.dropdown_link :if={@show_settings} {workspace_link(@context, "/teacher/settings")}><.icon
            name="hero-cog-6-tooth"
            class="size-4"
          />{gettext("Settings")}</.dropdown_link>
          <div
            data-ui={if @show_settings, do: "sign-out-group"}
            class={
              @show_settings &&
                "mt-[6px] pt-[6px] border-t border-t-line"
            }
          >
            <.dropdown_link :if={@preview} {workspace_link(@context, "/signed-out")}><.icon
              name="hero-arrow-right-start-on-rectangle"
              class="size-4"
            />{gettext("Sign out")}</.dropdown_link>
            <.dropdown_link :if={!@preview} href="/auth/logout" method="delete"><.icon
              name="hero-arrow-right-start-on-rectangle"
              class="size-4"
            />{gettext("Sign out")}</.dropdown_link>
          </div>
        </.dropdown>
      </div>
    </.header_frame>
    """
  end

  attr :context, :boolean, default: false
  slot :inner_block, required: true

  defp header_frame(assigns) do
    ~H"""
    <header class="border-b border-line bg-white shadow-[0_1px_0_#fff]">
      <div
        data-context={to_string(@context)}
        class={[
          "group/header mx-auto flex min-h-[76px] max-w-[1280px] items-center px-[32px] group-data-[public=true]/page:max-w-[1160px] max-[760px]:min-h-[68px] max-[760px]:flex-wrap max-[760px]:gap-[8px] max-[760px]:px-[20px] max-[760px]:pt-[12px]",
          if(@context,
            do:
              "gap-[22px] max-[760px]:pb-[10px] max-[760px]:after:order-1 max-[760px]:after:basis-full max-[760px]:after:content-['']",
            else: "gap-[44px]"
          )
        ]}
      >
        {render_slot(@inner_block)}
      </div>
    </header>
    """
  end

  slot :inner_block, required: true

  defp main_navigation(assigns) do
    ~H"""
    <nav
      data-ui="navigation"
      class={[
        "flex items-center self-stretch gap-[8px] max-[760px]:order-3 max-[760px]:w-full max-[760px]:gap-[12px] max-[760px]:pb-[10px]",
        "[&_a]:inline-flex [&_a]:items-center [&_a]:gap-[8px] [&_a]:rounded-[6px] [&_a]:px-[13px] [&_a]:py-[10px] [&_a]:text-[13px] [&_a]:font-[550] [&_a]:text-muted [&_a:hover]:bg-neutral-hover [&_a:hover]:text-body [&_a[aria-current]]:bg-neutral-hover [&_a[aria-current]]:text-body max-[760px]:[&_a]:px-[12px] max-[760px]:[&_a]:py-[9px]",
        "max-[760px]:group-data-[context=true]/header:ml-auto max-[760px]:group-data-[context=true]/header:w-auto max-[760px]:group-data-[context=true]/header:gap-0 max-[760px]:group-data-[context=true]/header:pb-0 max-[760px]:group-data-[context=true]/header:[&_a]:px-[8px] max-[760px]:group-data-[context=true]/header:[&_a]:text-[12px] max-[360px]:group-data-[context=true]/header:[&_a>span]:hidden"
      ]}
      aria-label={gettext("Main navigation")}
    >
      {render_slot(@inner_block)}
    </nav>
    """
  end

  attr :user, :map, required: true

  defp avatar(assigns) do
    ~H"""
    <.user_avatar src={Map.get(@user, :avatar_url)} aria-hidden="true">{@user.initials}</.user_avatar>
    """
  end

  defp context_label(:teaching), do: gettext("Teaching")
  defp context_label(:learning), do: gettext("Learning")
  defp context_label(:institution), do: gettext("Institution")
  defp context_label(:platform), do: gettext("Platform")
  defp context_icon(:teaching), do: "hero-academic-cap"
  defp context_icon(:learning), do: "hero-academic-cap"
  defp context_icon(:institution), do: "hero-building-library"
  defp context_icon(:platform), do: "hero-server-stack"
  defp context_path(:teaching), do: "/classrooms"
  defp context_path(:learning), do: "/student/classrooms"
  defp context_path(:institution), do: "/admin/institution"
  defp context_path(:platform), do: "/admin/platform"

  attr :context, :atom, default: :teaching
  attr :links, :map, default: %{}

  def footer(assigns) do
    assigns = assign(assigns, :version, Application.spec(:gradepush, :vsn) |> to_string())

    ~H"""
    <footer class="bg-white border-t border-t-[#dce3ef] text-muted text-[12px]">
      <div class={[
        "group-data-[public=true]/page:max-w-[1160px] flex items-center justify-between max-w-[1280px] py-[14px]",
        "px-[32px] m-auto gap-[20px] max-[760px]:py-[10px] max-[760px]:px-[20px]",
        "max-[760px]:[&:has([data-ui~=footer-links]_a:nth-child(2))]:items-start",
        "max-[760px]:[&:has([data-ui~=footer-links]_a:nth-child(2))]:flex-col",
        "max-[760px]:[&:has([data-ui~=footer-links]_a:nth-child(2))]:gap-[8px]"
      ]}>
        <div class="flex items-center gap-[12px] shrink-0">
          <.link
            {workspace_link(@context, "/classrooms")}
            class="flex items-center min-h-[44px] [&_img]:w-[96px] [&_img]:h-auto"
          >
            <img src={~p"/images/logo.svg"} width="96" alt="GradePush" />
          </.link>
          <span data-ui="app-version">v{@version}</span>
        </div>
        <nav
          data-ui="footer-links"
          class={[
            "flex items-center justify-end flex-wrap gap-y-[4px] gap-x-[24px] [&_a]:inline-flex [&_a]:items-center",
            "[&_a]:min-h-[44px] [&_a:hover]:text-ink [&_a:hover]:underline [&_a:hover]:underline-offset-[4px]",
            "max-[760px]:justify-start max-[760px]:gap-y-0 max-[760px]:gap-x-[20px]"
          ]}
          aria-label={gettext("Useful links")}
        >
          <a
            :for={
              {field, label} <- [
                {:support_url, gettext("Assistance")},
                {:privacy_url, gettext("Privacy")},
                {:accessibility_url, gettext("Accessibility")},
                {:terms_url, gettext("Terms of use")}
              ]
            }
            :if={@links[field] not in [nil, ""]}
            href={@links[field]}
          >{label}</a>
          <a
            href="https://github.com/gradepush"
            class="inline-flex items-center py-[8px] px-0 gap-[8px]"
          >
            <.icon name="github" /> GitHub
          </a>
        </nav>
      </div>
    </footer>
    """
  end

  defp workspace_link(:teaching, path), do: [patch: path]
  defp workspace_link(:learning, "/classrooms"), do: [navigate: "/student/classrooms"]
  defp workspace_link(_context, path), do: [navigate: path]

  defp context_link(current, target)
       when current == target or
              (current in [:institution, :platform] and target in [:institution, :platform]),
       do: [patch: context_path(target)]

  defp context_link(_current, target), do: [navigate: context_path(target)]
end
