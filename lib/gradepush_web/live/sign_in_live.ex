defmodule GradePushWeb.SignInLive do
  @moduledoc false
  use GradePushWeb, :live_view

  alias GradePushWeb.WorkspaceLayout

  @impl true
  def mount(_params, session, socket) do
    locale = if session["locale"] in ~w(en fr), do: session["locale"], else: "en"
    Gettext.put_locale(GradePushWeb.Gettext, locale)

    {:ok,
     assign(socket,
       page_title: gettext("Sign in with GitHub"),
       locale: locale,
       footer_links: GradePush.Accounts.footer_links()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page public>
      <div class="min-h-screen flex flex-col">
        <WorkspaceLayout.public_header locale={@locale} path="/auth/sign-in" />
        <.page_content>
          <.empty_state>
            <h1>{gettext("Sign in with GitHub")}</h1>
            <p>{gettext("Sign in with GitHub to return to your classrooms.")}</p>
            <.button href="/auth/github" variant="primary">{gettext("Continue on GitHub")}</.button>
            <.notice
              :if={Phoenix.Flash.get(@flash, :error)}
              kind="error"
              role="alert"
            >
              {Phoenix.Flash.get(@flash, :error)}
            </.notice>
          </.empty_state>
        </.page_content>
        <WorkspaceLayout.footer context={:public} links={@footer_links} />
      </div>
    </.page>
    """
  end
end
