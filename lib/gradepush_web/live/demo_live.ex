defmodule GradePushWeb.DemoLive do
  @moduledoc false
  use GradePushWeb, :live_view

  alias GradePush.Demo
  alias GradePushWeb.WorkspaceLayout

  @impl true
  def mount(_params, session, socket) do
    if Demo.enabled?() and Demo.mode() == :demo do
      locale = if session["locale"] in ~w(en fr), do: session["locale"], else: "en"
      Gettext.put_locale(GradePushWeb.Gettext, locale)

      {:ok,
       assign(socket,
         locale: locale,
         page_title: gettext("Try GradePush")
       )}
    else
      {:ok, Phoenix.LiveView.redirect(socket, to: "/auth/sign-in")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="class-preview">
      <div class="cp-shell">
        <WorkspaceLayout.public_header locale={@locale} path="/demo" />
        <main class="cp-main">
          <section class="cp-admin-panel cp-demo-panel">
            <div class="cp-admin-panel-heading">
              <p class="cp-context">GradePush</p>
              <h1>{gettext("Try the demo")}</h1>
              <p>
                {gettext("Choose a role to explore the demo with sample classrooms and assignments.")}
              </p>
            </div>
            <div class="cp-demo-roles">
              <form action="/demo/sign-in" method="post">
                <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
                <input type="hidden" name="role" value="teacher" />
                <input type="hidden" name="locale" value={@locale} />
                <button type="submit" class="cp-button cp-primary">{gettext("Continue as a teacher")}</button>
              </form>
              <form action="/demo/sign-in" method="post">
                <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
                <input type="hidden" name="role" value="student" />
                <input type="hidden" name="locale" value={@locale} />
                <button type="submit" class="cp-button">{gettext("Continue as a student")}</button>
              </form>
            </div>
            <p :if={Phoenix.Flash.get(@flash, :error)} class="cp-error" role="alert">
              {Phoenix.Flash.get(@flash, :error)}
            </p>
          </section>
        </main>
        <WorkspaceLayout.footer />
      </div>
    </div>
    """
  end
end
