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
    <div class="cp-heading">
      <div>
        <h1>{gettext("Settings")}</h1><p class="cp-lead">
          {gettext("Your GitHub account and the organizations you teach with.")}
        </p>
      </div>
    </div>
    <div class="cp-settings">
      <p :if={@error} class="cp-error" role="alert">{@error}</p>
      <p :if={@notice} class="cp-notice" role="status">{@notice}</p>
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
          <img
            :if={Map.get(@user, :avatar_url)}
            class="cp-avatar"
            src={Map.get(@user, :avatar_url)}
            alt=""
          />
          <span :if={!Map.get(@user, :avatar_url)} class="cp-avatar" aria-hidden="true">{@user.initials}</span>
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
          <p :if={@organizations == []} class="cp-empty-inline">
            {gettext("Connect a GitHub organization before creating a classroom.")}
          </p>
          <div :for={organization <- @organizations} class="cp-organization-row">
            <span class="cp-organization-icon"><.icon name="hero-building-office-2" class="size-5" /></span>
            <div>
              <strong>{organization_name(organization)}</strong>
              <span>{sharing_description(organization, Map.get(@user, :id))}</span>
            </div>
            <span class="cp-connection-state"><span></span>{gettext("Connected")}</span>
            <form
              :if={
                shareable?(organization, Map.get(@user, :id)) and
                  shareable_teachers(organization, @sharing_teachers) != []
              }
              phx-submit="share_organization"
              class="cp-organization-share"
            >
              <input type="hidden" name="connection_id" value={organization.id} />
              <label>
                <span class="sr-only">{gettext("Choose a teacher to share with")}</span>
                <select name="teacher_id" required>
                  <option value="">{gettext("Share with a teacher")}</option>
                  <option
                    :for={teacher <- shareable_teachers(organization, @sharing_teachers)}
                    value={teacher.id}
                  >
                    {teacher.name}
                  </option>
                </select>
              </label>
              <button class="cp-button">{gettext("Share")}</button>
            </form>
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
    assigns = assign_new(assigns, :preview, fn -> true end)

    ~H"""
    <section class="cp-sign-in">
      <span class="cp-sign-in-icon"><.icon name="hero-academic-cap" class="size-8" /></span>
      <h1>{gettext("See you soon")}</h1>
      <p>{gettext("Sign in with GitHub to return to your classrooms.")}</p>
      <.link :if={@preview} patch="/classrooms" class="cp-button cp-primary">{gettext(
        "Sign in with GitHub"
      )}<.icon
        name="hero-arrow-right"
        class="size-4"
      /></.link>
      <.link :if={!@preview} href="/auth/github" class="cp-button cp-primary">{gettext(
        "Sign in with GitHub"
      )}<.icon
        name="hero-arrow-right"
        class="size-4"
      /></.link>
      <p :if={@preview} class="cp-preview-note">
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
