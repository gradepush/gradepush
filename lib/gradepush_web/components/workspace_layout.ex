defmodule GradePushWeb.WorkspaceLayout do
  @moduledoc false
  use GradePushWeb, :html

  attr :user, :map, required: true
  attr :institution, :string, required: true
  attr :action, :atom, required: true
  attr :locale, :string, required: true
  attr :language_urls, :map, required: true

  def header(assigns) do
    assigns = assign(assigns, :target_locale, if(assigns.locale == "fr", do: "en", else: "fr"))

    ~H"""
    <header class="cp-header">
      <div class="cp-header-inner">
        <.link patch="/classrooms" class="cp-logo">
          <img src={~p"/images/logo.svg"} width="140" alt="GradePush" />
        </.link>
        <nav
          :if={@action != :signed_out}
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
              <span class="cp-avatar" aria-hidden="true">{@user.initials}</span>
              <.icon name="hero-chevron-down" class="size-3" />
            </summary>
            <div class="cp-dropdown cp-profile-menu">
              <div class="cp-profile-identity">
                <span class="cp-avatar" aria-hidden="true">{@user.initials}</span>
                <div><strong>{@user.name}</strong><span>@{@user.handle}</span></div>
              </div>
              <div class="cp-profile-institution">
                <.icon name="hero-building-library" class="size-4" />
                <span>{@institution}</span>
              </div>
              <.link patch="/teacher/settings"><.icon name="hero-cog-6-tooth" class="size-4" />{gettext(
                "Settings"
              )}</.link>
              <div class="cp-sign-out-group">
                <.link patch="/signed-out"><.icon
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

  def footer(assigns) do
    ~H"""
    <footer class="cp-footer">
      <div class="cp-footer-inner">
        <.link patch="/classrooms" class="cp-footer-brand">GradePush</.link>
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
end
