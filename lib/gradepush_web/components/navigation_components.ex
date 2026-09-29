defmodule GradePushWeb.NavigationComponents do
  @moduledoc "Shared section navigation and disclosure menus."
  use Phoenix.Component
  import GradePushWeb.CoreComponents, only: [icon: 1]

  attr :id, :string, default: nil
  attr :label, :string, required: true
  attr :compact, :boolean, default: false
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def tabs(assigns) do
    ~H"""
    <nav
      data-ui="tabs"
      id={@id}
      class={[
        "mt-[28px] flex w-fit max-w-full gap-[5px] overflow-x-auto rounded-[14px] border border-line bg-tab-track p-[5px]",
        @compact &&
          [
            "max-[760px]:grid max-[760px]:auto-cols-[minmax(max-content,1fr)] max-[760px]:grid-flow-col max-[760px]:overflow-x-auto",
            "max-[760px]:[&>a]:flex-col max-[760px]:[&>a]:gap-[6px] max-[760px]:[&>a]:px-[12px]",
            "max-[760px]:[&>a]:py-[12px] max-[760px]:[&>a]:text-[11px] max-[760px]:[&>a]:whitespace-nowrap"
          ],
        @class
      ]}
      aria-label={@label}
    >
      {render_slot(@inner_block)}
    </nav>
    """
  end

  attr :active, :boolean, default: false
  attr :count, :integer, default: nil
  attr :rest, :global, include: ~w(patch navigate href)
  slot :inner_block, required: true

  def tab(assigns) do
    ~H"""
    <.link
      class={[
        "flex min-h-[44px] shrink-0 items-center justify-center gap-[9px] whitespace-nowrap rounded-[10px] px-[16px] py-[11px] font-[550] focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-brand max-[760px]:gap-[6px] max-[760px]:px-[12px] max-[760px]:text-[13px]",
        @active && "is-active bg-white text-brand shadow-tab",
        !@active && "text-muted hover:bg-white/60 hover:text-ink"
      ]}
      aria-current={if @active, do: "page"}
      {@rest}
    >
      {render_slot(@inner_block)}
      <span
        :if={!is_nil(@count)}
        class={[
          "rounded-[5px] px-1.5 py-px text-[11px]",
          if(@active, do: "bg-[#edf2ff] text-brand", else: "bg-[#f1f3f7] text-muted")
        ]}
      >{@count}</span>
    </.link>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :kind, :string, default: "profile", values: ~w(profile context)
  slot :trigger, required: true
  slot :inner_block, required: true

  def dropdown(assigns) do
    ~H"""
    <details
      id={@id}
      name="header-menu"
      class={["relative", @kind == "context" && "max-[760px]:order-2"]}
      phx-hook="HeaderDisclosure"
    >
      <summary
        aria-label={@label}
        title={@label}
        class={[
          "flex min-h-[44px] cursor-pointer list-none items-center rounded-[7px] text-muted [&::-webkit-details-marker]:hidden hover:text-ink",
          if(@kind == "context",
            do: "gap-[8px] border border-line px-[10px] py-[8px] text-[12px] hover:bg-[#f9fafb]",
            else: "justify-center gap-[8px] p-[5px]"
          )
        ]}
      >
        {render_slot(@trigger)}
        <.icon name="hero-chevron-down" class="size-3" />
      </summary>
      <div class={[
        "absolute top-[calc(100%+10px)] z-40 rounded-[9px] border border-[#e0e5ee] bg-white p-[6px] shadow-[0_8px_24px_#20283814]",
        if(@kind == "context", do: "left-0 w-[220px]", else: "right-0 w-[270px]")
      ]}>
        {render_slot(@inner_block)}
      </div>
    </details>
    """
  end

  attr :rest, :global, include: ~w(patch navigate href method)
  slot :inner_block, required: true

  def dropdown_link(assigns) do
    ~H"""
    <.link
      class="flex min-h-[42px] items-center gap-[10px] rounded-[5px] p-[10px] text-[13px] hover:bg-[#f3f5f8]"
      {@rest}
    >{render_slot(@inner_block)}</.link>
    """
  end
end
