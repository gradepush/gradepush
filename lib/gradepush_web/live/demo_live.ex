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
         page_title: GradePushWeb.Metadata.demo_title()
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
          <div class="mx-auto max-w-[960px] pt-[28px] max-[760px]:pt-[8px]">
            <header class="mx-auto mb-[36px] max-w-[620px] text-center">
              <.eyebrow>{gettext("Interactive demo")}</.eyebrow>
              <h1 class="mt-[12px] text-[38px] font-[650] leading-[1.15] tracking-[-1px] max-[760px]:text-[30px]">
                {gettext("A classroom. Two perspectives.")}
              </h1>
              <p class="mt-[18px] text-[16px] leading-[1.65] text-muted max-[760px]:text-[14px]">
                {GradePushWeb.Metadata.demo_description()}
              </p>
            </header>
            <div class="grid grid-cols-2 gap-[24px] max-[760px]:grid-cols-1 max-[760px]:gap-[18px]">
              <.role_card
                role="teacher"
                locale={@locale}
                icon="hero-presentation-chart-bar"
                title={gettext("Teacher")}
                description={gettext("Organize your classes and follow your students’ work.")}
                action={gettext("Continue as a teacher")}
              >
                <:feature icon="hero-document-text">
                  {gettext("Create and share assignments")}
                </:feature>
                <:feature icon="hero-chart-bar">
                  {gettext("Follow pushes and automated test results")}
                </:feature>
                <:feature icon="hero-user-group">
                  {gettext("Manage students and teaching colleagues")}
                </:feature>
              </.role_card>
              <.role_card
                role="student"
                locale={@locale}
                icon="hero-academic-cap"
                title={gettext("Student")}
                description={
                  gettext("Find your next assignment and see how your work is progressing.")
                }
                action={gettext("Continue as a student")}
              >
                <:feature icon="hero-calendar-days">
                  {gettext("Browse your classes and deadlines")}
                </:feature>
                <:feature icon="hero-code-bracket">
                  {gettext("Read instructions and find your repository")}
                </:feature>
                <:feature icon="hero-check-circle">
                  {gettext("See which automated tests passed")}
                </:feature>
              </.role_card>
            </div>
            <.notice
              :if={Phoenix.Flash.get(@flash, :error)}
              kind="error"
              role="alert"
            >
              {Phoenix.Flash.get(@flash, :error)}
            </.notice>
          </div>
        </.page_content>
        <WorkspaceLayout.footer context={:public} links={@footer_links} />
      </div>
    </.page>
    """
  end

  attr :role, :string, required: true, values: ~w(teacher student)
  attr :locale, :string, required: true
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :action, :string, required: true

  slot :feature, required: true do
    attr :icon, :string, required: true
  end

  defp role_card(assigns) do
    ~H"""
    <.panel
      aria-labelledby={"demo-#{@role}-title"}
      class="!mb-0 flex flex-col shadow-classroom"
    >
      <div class="flex-1 px-[32px] pt-[32px] pb-[28px] max-[760px]:p-[24px]">
        <span class="mb-[24px] inline-flex size-[52px] items-center justify-center rounded-[14px] border border-brand/10 bg-brand-soft text-brand">
          <.icon name={@icon} class="size-[28px]" />
        </span>
        <h2 id={"demo-#{@role}-title"} class="!text-[24px] tracking-[-.5px]">{@title}</h2>
        <p class="mt-[10px] min-h-[48px] text-[14px] leading-[1.7] text-muted">
          {@description}
        </p>
        <ul class="mt-[26px] space-y-[16px] border-t border-line pt-[24px]">
          <li :for={feature <- @feature} class="flex items-start gap-[12px] text-[13px] leading-[1.6]">
            <.icon name={feature.icon} class="mt-[1px] size-[19px] shrink-0 text-muted" />
            <span>{render_slot(feature)}</span>
          </li>
        </ul>
      </div>
      <form
        action="/demo/sign-in"
        method="post"
        class="border-t border-line bg-surface-heading p-[24px]"
      >
        <.input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
        <.input type="hidden" name="role" value={@role} />
        <.input type="hidden" name="locale" value={@locale} />
        <.button
          type="submit"
          variant={if @role == "teacher", do: "primary", else: "secondary"}
          class="w-full"
        >
          {@action}<.icon name="hero-arrow-right" class="size-4" />
        </.button>
      </form>
    </.panel>
    """
  end
end
