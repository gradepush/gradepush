defmodule GradePushWeb.WorkspaceLayout do
  @moduledoc false
  use GradePushWeb, :html

  attr :locale, :string, required: true
  attr :path, :string, required: true

  def public_header(assigns) do
    assigns = assign(assigns, :target_locale, if(assigns.locale == "fr", do: "en", else: "fr"))

    ~H"""
    <header class="cp-header">
      <div class="cp-header-inner">
        <a href="/" class="cp-logo"><img src="/images/logo.svg" width="140" alt="GradePush" /></a>
        <div class="cp-account">
          <.link
            href={@path <> "?locale=" <> @target_locale}
            lang={@target_locale}
            class="cp-language"
            aria-label={
              if @target_locale == "en", do: "Switch to English", else: "Passer en français"
            }
          >
            <.icon name="hero-globe-alt" class="size-4" />{String.upcase(@target_locale)}
          </.link>
        </div>
      </div>
    </header>
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
    <header class="cp-header">
      <div class="cp-header-inner">
        <.link {workspace_link(@context, "/classrooms")} class="cp-logo">
          <img src={~p"/images/logo.svg"} width="140" alt="GradePush" />
        </.link>
        <details
          :if={@action != :signed_out and length(@contexts) > 1}
          id="context-menu"
          name="header-menu"
          class="cp-disclosure cp-context-switcher"
          phx-hook="HeaderDisclosure"
        >
          <summary class="cp-context-trigger" aria-label={gettext("Switch workspace")}>
            <.icon name={context_icon(@context)} class="size-4" />
            <span>{context_label(@context)}</span>
            <.icon name="hero-chevron-down" class="size-3" />
          </summary>
          <div class="cp-dropdown cp-context-menu">
            <.link
              :for={context <- @contexts}
              {context_link(@context, context)}
              aria-current={if context == @context, do: "true"}
            >
              <.icon name={context_icon(context)} class="size-4" />
              {context_label(context)}
              <.icon :if={context == @context} name="hero-check" class="size-4 cp-context-check" />
            </.link>
          </div>
        </details>
        <nav
          :if={@action != :signed_out and @context == :teaching}
          class="cp-navigation"
          aria-label={gettext("Main navigation")}
        >
          <.link patch="/classrooms" aria-current={if @action != :settings, do: "page"}>
            <.icon name="hero-rectangle-stack" class="size-4" />{gettext("Classrooms")}
          </.link>
          <.link patch="/teacher/settings" aria-current={if @action == :settings, do: "page"}>
            <.icon name="hero-cog-6-tooth" class="size-4" />{gettext("Settings")}
          </.link>
        </nav>
        <nav :if={@context == :learning} class="cp-navigation" aria-label={gettext("Main navigation")}>
          <.link navigate="/student/classrooms" aria-current="page">
            <.icon name="hero-rectangle-stack" class="size-4" />{gettext("Classrooms")}
          </.link>
        </nav>
        <div class="cp-account">
          <.link
            href={Map.fetch!(@language_urls, @target_locale)}
            lang={@target_locale}
            class="cp-language"
            aria-label={
              if @target_locale == "en", do: "Switch to English", else: "Passer en français"
            }
          >
            <.icon name="hero-globe-alt" class="size-4" />{String.upcase(@target_locale)}
          </.link>
          <details
            :if={@action != :signed_out}
            id="profile-menu"
            name="header-menu"
            class="cp-disclosure"
            phx-hook="HeaderDisclosure"
          >
            <summary
              class="cp-profile-button"
              aria-label={gettext("Account menu")}
              title={gettext("Account menu")}
            >
              <.avatar user={@user} />
              <.icon name="hero-chevron-down" class="size-3" />
            </summary>
            <div class="cp-dropdown cp-profile-menu">
              <div class="cp-profile-identity">
                <.avatar user={@user} />
                <div><strong>{@user.name}</strong><span>@{@user.handle}</span></div>
              </div>
              <div class={["cp-profile-institution", @show_settings && "cp-profile-divider"]}>
                <.icon name="hero-building-library" class="size-4" />
                <span>{@institution}</span>
              </div>
              <.link :if={@show_settings} {workspace_link(@context, "/teacher/settings")}><.icon
                name="hero-cog-6-tooth"
                class="size-4"
              />{gettext("Settings")}</.link>
              <div class={@show_settings && "cp-sign-out-group"}>
                <.link :if={@preview} {workspace_link(@context, "/signed-out")}><.icon
                  name="hero-arrow-right-start-on-rectangle"
                  class="size-4"
                />{gettext("Sign out")}</.link>
                <.link :if={!@preview} href="/auth/logout" method="delete"><.icon
                  name="hero-arrow-right-start-on-rectangle"
                  class="size-4"
                />{gettext("Sign out")}</.link>
              </div>
            </div>
          </details>
        </div>
      </div>
    </header>
    """
  end

  attr :user, :map, required: true

  defp avatar(assigns) do
    ~H"""
    <img
      :if={Map.get(@user, :avatar_url)}
      class="cp-avatar object-cover"
      src={@user.avatar_url}
      alt=""
    />
    <span :if={!Map.get(@user, :avatar_url)} class="cp-avatar" aria-hidden="true">{@user.initials}</span>
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

  def footer(assigns) do
    ~H"""
    <footer class="cp-footer">
      <div class="cp-footer-inner">
        <.link {workspace_link(@context, "/classrooms")} class="cp-footer-brand">GradePush</.link>
        <span class="cp-footer-github">
          <svg viewBox="0 0 24 24" class="size-4" fill="currentColor" aria-hidden="true">
            <path d="M12 .297a12 12 0 0 0-3.793 23.384c.6.111.82-.261.82-.577v-2.234c-3.338.726-4.043-1.416-4.043-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.09-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.071 1.835 2.809 1.305 3.495.998.108-.776.419-1.305.762-1.605-2.665-.305-5.467-1.334-5.467-5.931 0-1.31.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.323 3.301 1.23a11.52 11.52 0 0 1 6.006 0c2.291-1.553 3.297-1.23 3.297-1.23.653 1.652.242 2.873.119 3.176.769.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.216.694.825.576A12 12 0 0 0 12 .297Z" />
          </svg>
          GitHub
        </span>
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
