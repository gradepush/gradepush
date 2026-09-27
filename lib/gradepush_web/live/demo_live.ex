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
         footer_links: GradePush.Accounts.footer_links(),
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
    <.page public>
      <div class="min-h-screen flex flex-col">
        <WorkspaceLayout.public_header locale={@locale} path="/demo" />
        <.page_content>
          <.panel class={[
            "max-w-[640px] my-[40px] mx-auto [&_[data-ui~=admin-panel-heading]]:block [&_h1]:text-[26px]",
            "[&_h1]:font-[650] [&_h1]:leading-[1.25] [&_h1]:my-[8px] [&_h1]:mx-0"
          ]}>
            <.panel_heading>
              <.eyebrow>
                GradePush
              </.eyebrow>
              <h1>{gettext("Try the demo")}</h1>
              <p>
                {gettext("Choose a role to explore the demo with sample classrooms and assignments.")}
              </p>
            </.panel_heading>
            <div class="flex flex-wrap p-[24px] gap-[12px] [&_form]:flex-[1_1_220px] [&_button]:w-full">
              <form action="/demo/sign-in" method="post">
                <.input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
                <.input type="hidden" name="role" value="teacher" />
                <.input type="hidden" name="locale" value={@locale} />
                <.button type="submit" variant="primary">{gettext("Continue as a teacher")}</.button>
              </form>
              <form action="/demo/sign-in" method="post">
                <.input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
                <.input type="hidden" name="role" value="student" />
                <.input type="hidden" name="locale" value={@locale} />
                <.button type="submit">{gettext("Continue as a student")}</.button>
              </form>
            </div>
            <.notice
              :if={Phoenix.Flash.get(@flash, :error)}
              kind="error"
              role="alert"
            >
              {Phoenix.Flash.get(@flash, :error)}
            </.notice>
          </.panel>
        </.page_content>
        <WorkspaceLayout.footer context={:public} links={@footer_links} />
      </div>
    </.page>
    """
  end
end
