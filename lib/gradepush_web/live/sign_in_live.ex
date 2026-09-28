defmodule GradePushWeb.SignInLive do
  @moduledoc false
  use GradePushWeb, :live_view

  alias GradePushWeb.OnboardingComponents

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
    <OnboardingComponents.frame
      locale={@locale}
      path="/auth/sign-in"
      eyebrow="GradePush"
      title={gettext("Welcome to your classroom")}
      description={gettext("Your classes, assignments, and code, together in one place.")}
      footer_links={@footer_links}
    >
      <:overview>
        <dl class="space-y-[24px]">
          <div class="flex items-start gap-[14px]">
            <span class="inline-flex size-[38px] shrink-0 items-center justify-center rounded-[10px] bg-brand-soft text-brand"><.icon
              name="hero-presentation-chart-bar"
              class="size-5"
            /></span>
            <div>
              <dt class="text-[14px] font-semibold">{gettext("Teachers")}</dt><dd class="mt-[5px] text-[13px] leading-[1.65] text-muted">
                {gettext("Organize your classes and follow your students’ work.")}
              </dd>
            </div>
          </div>
          <div class="flex items-start gap-[14px]">
            <span class="inline-flex size-[38px] shrink-0 items-center justify-center rounded-[10px] bg-brand-soft text-brand"><.icon
              name="hero-academic-cap"
              class="size-5"
            /></span>
            <div>
              <dt class="text-[14px] font-semibold">{gettext("Students")}</dt><dd class="mt-[5px] text-[13px] leading-[1.65] text-muted">
                {gettext("Find your assignments, deadlines, and test results.")}
              </dd>
            </div>
          </div>
        </dl>
      </:overview>
      <.panel_heading>
        <.icon name="hero-user-circle" class="size-5 text-brand" />
        <h2>{gettext("Sign in with GitHub")}</h2>
      </.panel_heading>
      <div class="p-[28px] max-[760px]:p-[22px]">
        <.notice :if={Phoenix.Flash.get(@flash, :error)} kind="error" role="alert">
          {Phoenix.Flash.get(@flash, :error)}
        </.notice>
        <p class="text-[14px] leading-[1.7] text-muted">
          {gettext("Use your GitHub account to access your GradePush workspace.")}
        </p>
        <.button href="/auth/github" variant="primary" class="my-[24px] w-full">
          <.icon name="github" class="size-5" />{gettext("Continue on GitHub")}
        </.button>
        <p class="flex items-start gap-[10px] border-t border-line pt-[20px] text-[12px] leading-[1.7] text-muted">
          <.icon name="hero-link" class="mt-[2px] size-4 shrink-0" />
          <span>{gettext(
            "Joining a new class? Open the invitation link your teacher shared with you."
          )}</span>
        </p>
      </div>
    </OnboardingComponents.frame>
    """
  end
end
