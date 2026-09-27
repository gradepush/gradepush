defmodule GradePushWeb.AccountComponents do
  @moduledoc false
  use GradePushWeb, :html

  attr :user, :map, required: true
  attr :organizations, :list, required: true
  attr :section, :string, required: true

  def settings(assigns) do
    ~H"""
    <div class="cp-heading">
      <div>
        <h1>{gettext("Settings")}</h1><p class="cp-lead">
          {gettext("Your GitHub account and the organizations you teach with.")}
        </p>
      </div>
    </div>
    <div class="cp-settings">
      <nav class="cp-settings-nav" aria-label={gettext("Account settings")}>
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
      <section
        :if={@section == "account"}
        class="cp-settings-panel"
        aria-labelledby="github-account-title"
      >
        <div class="cp-settings-panel-heading">
          <h2 id="github-account-title">{gettext("GitHub account")}</h2>
        </div>
        <div class="cp-connected-account">
          <span class="cp-avatar" aria-hidden="true">{@user.initials}</span>
          <div>
            <strong>{@user.name}</strong><a
              href={"https://github.com/#{@user.handle}"}
              target="_blank"
              rel="noopener noreferrer"
            >@{@user.handle}<.icon name="hero-arrow-up-right" class="size-3" /></a>
          </div>
          <span class="cp-connection-state"><span></span>{gettext("Connected")}</span>
        </div>
      </section>
      <section
        :if={@section == "organizations"}
        class="cp-settings-panel"
        aria-labelledby="github-organizations-title"
      >
        <div class="cp-settings-panel-heading">
          <h2 id="github-organizations-title">{gettext("GitHub organizations")}</h2>
          <p>{gettext("Choose a connected organization when creating a classroom.")}</p>
        </div>
        <div>
          <div :for={organization <- @organizations} class="cp-organization-row">
            <span class="cp-organization-icon"><.icon name="hero-building-office-2" class="size-5" /></span>
            <div>
              <strong>{organization}</strong><span>{gettext("Shared with your colleagues")}</span>
            </div>
            <span class="cp-connection-state"><span></span>{gettext("Connected")}</span>
          </div>
          <div class="cp-settings-actions">
            <button
              class="cp-button"
              phx-click={JS.push_focus() |> JS.push("open", value: %{kind: "connect_organization"})}
            >
              <.icon name="hero-plus" class="size-4" />{gettext("Connect an organization")}
            </button>
          </div>
        </div>
      </section>
    </div>
    """
  end

  def signed_out(assigns) do
    ~H"""
    <section class="cp-sign-in">
      <span class="cp-sign-in-icon"><.icon name="hero-academic-cap" class="size-8" /></span>
      <h1>{gettext("See you soon")}</h1>
      <p>{gettext("Sign in with GitHub to return to your classrooms.")}</p>
      <.link patch="/classrooms" class="cp-button cp-primary">{gettext("Sign in with GitHub")}<.icon
        name="hero-arrow-right"
        class="size-4"
      /></.link>
      <p class="cp-preview-note">{gettext("Sign-in and sign-out are simulated in this preview.")}</p>
    </section>
    """
  end
end
