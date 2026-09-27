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

  attr :section, :string, required: true
  attr :user, :map, required: true
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
        <.panel>
          <.panel_heading>
            <.icon name="hero-key" class="size-5" /><div>
              <h2>{gettext("Platform access")}</h2><p>
                {gettext("Platform access is separate from institution administration.")}
              </p>
            </div>
          </.panel_heading>
          <div class={[
            "flex items-center p-[22px] gap-[12px] [&_strong]:text-[14px] [&_strong]:font-[550] [&_p]:text-muted",
            "[&_p]:text-[12px] [&>[data-ui~=admin-tag]]:ml-auto"
          ]}>
            <.user_avatar size="default">{@user.initials}</.user_avatar><div>
              <strong>{@user.name}</strong><p>@{@user.handle}</p>
            </div><.badge>{gettext("Operator")}</.badge>
          </div>
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
