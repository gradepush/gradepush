defmodule GradePushWeb.OnboardingComponents do
  @moduledoc "Shared layout for first-run setup and GitHub sign-in."
  use GradePushWeb, :html

  alias GradePushWeb.WorkspaceLayout

  attr :locale, :string, required: true
  attr :path, :string, required: true
  attr :eyebrow, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :footer_links, :map, default: %{}
  slot :overview
  slot :inner_block, required: true

  def frame(assigns) do
    ~H"""
    <.page public>
      <div class="flex min-h-screen flex-col">
        <a class="skip-link" href="#onboarding-content">{gettext("Skip to content")}</a>
        <WorkspaceLayout.public_header locale={@locale} path={@path} />
        <.page_content id="onboarding-content" tabindex="-1">
          <div class="mx-auto grid max-w-[1020px] grid-cols-[minmax(0,.9fr)_minmax(0,1.1fr)] items-start gap-[64px] py-[48px] max-[1000px]:gap-[32px] max-[760px]:grid-cols-1 max-[760px]:gap-[28px] max-[760px]:py-[8px]">
            <div class="pt-[12px] max-[760px]:contents">
              <div>
                <.eyebrow>{@eyebrow}</.eyebrow>
                <h1 class="mt-[12px] text-[36px] font-[650] leading-[1.16] tracking-[-1px] max-[760px]:text-[30px]">
                  {@title}
                </h1>
                <p class="mt-[18px] text-[15px] leading-[1.7] text-muted">{@description}</p>
              </div>
              <div :if={@overview != []} class="mt-[32px] max-[760px]:order-2 max-[760px]:mt-0">
                {render_slot(@overview)}
              </div>
            </div>
            <.panel class="!mb-0 shadow-classroom max-[760px]:order-1">
              {render_slot(@inner_block)}
            </.panel>
          </div>
        </.page_content>
        <WorkspaceLayout.footer context={:public} links={@footer_links} />
      </div>
    </.page>
    """
  end

  attr :number, :integer, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  def setup_step(assigns) do
    ~H"""
    <li class="flex items-start gap-[14px]">
      <span
        aria-hidden="true"
        class="inline-flex size-[30px] shrink-0 items-center justify-center rounded-full border border-brand/10 bg-brand-soft text-[12px] font-semibold text-brand"
      >{@number}</span>
      <div class="pt-[3px]">
        <h2 class="text-[14px] font-semibold">{@title}</h2>
        <p class="mt-[5px] text-[13px] leading-[1.65] text-muted">{render_slot(@inner_block)}</p>
      </div>
    </li>
    """
  end
end
