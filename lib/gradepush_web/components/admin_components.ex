defmodule GradePushWeb.AdminComponents do
  @moduledoc false
  use GradePushWeb, :html

  attr :events, :list, required: true

  def history(assigns) do
    ~H"""
    <div class="cp-admin-section-heading">
      <div>
        <h2>{gettext("Administrative history")}</h2><p>{gettext("Who changed what, and when.")}</p>
      </div><span class="cp-admin-tag">{gettext("Read only")}</span>
    </div>
    <div :if={@events == []} class="cp-empty">
      <.icon name="hero-clock" class="size-8" /><h3>{gettext("No administrative changes yet")}</h3>
    </div>
    <ol :if={@events != []} class="cp-audit-list">
      <li :for={event <- @events}>
        <span class="cp-audit-icon"><.icon name="hero-clock" class="size-4" /></span>
        <div>
          <strong>{event.action}</strong><p>{event.target}</p><span>{event.actor}</span>
        </div>
        <time>{event.time}</time>
      </li>
    </ol>
    """
  end

  attr :section, :string, required: true
  attr :user, :map, required: true
  attr :platform, :map, required: true

  def platform(assigns) do
    ~H"""
    <%= case @section do %>
      <% "configuration" -> %>
        <section class="cp-admin-panel">
          <div class="cp-admin-panel-heading">
            <.icon name="hero-server-stack" class="size-5" /><div>
              <h2>{gettext("Instance configuration")}</h2><p>
                {gettext("Connection details for this GradePush installation.")}
              </p>
            </div><span :if={Map.get(@platform, :preview?, true)} class="cp-admin-tag">{gettext(
              "Example"
            )}</span>
          </div>
          <dl class="cp-admin-properties">
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
          <p class="cp-admin-panel-note">
            {gettext("Server configuration is managed by the installation operator.")}
          </p>
        </section>
        <section class="cp-admin-panel">
          <div class="cp-admin-panel-heading">
            <.icon name="hero-key" class="size-5" /><div>
              <h2>{gettext("Platform access")}</h2><p>
                {gettext("Platform access is separate from institution administration.")}
              </p>
            </div>
          </div>
          <div class="cp-admin-operator">
            <span class="cp-avatar">{@user.initials}</span><div>
              <strong>{@user.name}</strong><p>@{@user.handle}</p>
            </div><span class="cp-admin-tag">{gettext("Operator")}</span>
          </div>
        </section>
      <% "services" -> %>
        <div class="cp-admin-section-heading">
          <div>
            <h2>{gettext("Service status")}</h2><p>
              {gettext("Application connections and background work.")}
            </p>
          </div><span :if={Map.get(@platform, :preview?, true)} class="cp-admin-tag">{gettext(
            "Simulated status"
          )}</span>
        </div>
        <div class="cp-service-list">
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
    <div class="cp-service-row">
      <span class="cp-organization-icon"><.icon name={@icon} class="size-5" /></span><div>
        <h3>{@name}</h3><p>{@detail}</p>
      </div><span :if={@preview} class="cp-connection-state"><.icon
        name="hero-check-circle"
        class="size-4"
      />{gettext("Available")}</span>
    </div>
    """
  end
end
