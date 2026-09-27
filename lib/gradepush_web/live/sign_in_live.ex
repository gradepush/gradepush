defmodule GradePushWeb.SignInLive do
  @moduledoc false
  use GradePushWeb, :live_view

  alias GradePushWeb.WorkspaceLayout

  @impl true
  def mount(_params, session, socket) do
    locale = if session["locale"] in ~w(en fr), do: session["locale"], else: "en"
    Gettext.put_locale(GradePushWeb.Gettext, locale)
    {:ok, assign(socket, page_title: gettext("Sign in with GitHub"), locale: locale)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="class-preview">
      <div class="cp-shell">
        <WorkspaceLayout.public_header locale={@locale} path="/auth/sign-in" />
        <main class="cp-main">
          <div class="cp-empty">
            <h1>{gettext("Sign in with GitHub")}</h1>
            <p>{gettext("Sign in with GitHub to return to your classrooms.")}</p>
            <a href="/auth/github" class="cp-button cp-primary">{gettext("Continue on GitHub")}</a>
            <p :if={Phoenix.Flash.get(@flash, :error)} class="cp-error" role="alert">
              {Phoenix.Flash.get(@flash, :error)}
            </p>
          </div>
        </main>
      </div>
    </div>
    """
  end
end
