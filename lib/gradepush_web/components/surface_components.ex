defmodule GradePushWeb.SurfaceComponents do
  @moduledoc "Shared page structure, panels, and content groups."
  use Phoenix.Component

  attr :public, :boolean, default: false
  slot :inner_block, required: true

  def page(assigns) do
    ~H"""
    <div
      data-ui={if @public, do: "public", else: "workspace"}
      data-public={@public}
      class={[
        "group/page min-h-screen text-[14px] leading-[1.5] text-body",
        if(@public, do: "bg-[#f9fafb] [--color-line:#e5e9f0]", else: "bg-canvas")
      ]}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :student, :boolean, default: false
  attr :rest, :global
  slot :inner_block, required: true

  def page_content(assigns) do
    ~H"""
    <main
      class={[
        "mx-auto w-full max-w-[1280px] flex-1 px-[32px] pt-[36px] pb-[64px] focus:outline-none group-data-[public=true]/page:max-w-[1160px] max-[760px]:px-[20px] max-[760px]:pt-[28px] max-[760px]:pb-[48px] max-[760px]:group-data-[public=true]/page:pt-[24px]",
        @student &&
          "[&_[data-ui~=heading]_h1:last-child]:mb-0 [&_[data-ui~=class-meta]>span]:min-w-0 [&_[data-ui~=class-meta]>span]:wrap-anywhere [&_[data-ui~=class-meta]>span>.size-4]:shrink-0"
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </main>
    """
  end

  attr :variant, :string,
    default: "default",
    values: ~w(default classroom assignment student admin)

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def page_heading(assigns) do
    ~H"""
    <div
      data-ui={
        Enum.join(
          [
            "heading",
            @variant == "classroom" && "class-heading",
            @variant == "assignment" && "assignment-heading"
          ]
          |> Enum.filter(& &1),
          " "
        )
      }
      class={[
        "group-data-[public=true]/page:mb-[48px] group-data-[public=true]/page:[&_h1]:text-[30px] group-data-[public=true]/page:[&_h1]:leading-[1.25] group-data-[public=true]/page:[&_h1]:tracking-[-.9px] max-[760px]:group-data-[public=true]/page:mb-[32px] max-[760px]:group-data-[public=true]/page:[&_h1]:text-[27px] [&_h1]:mt-[8px] [&_h1]:wrap-anywhere [&_h1]:font-[650] [&_h1]:leading-[1.18] [&_[data-ui~=context]]:mb-[10px] [&_[data-ui~=lead]]:mt-[14px] [&_[data-ui~=lead]]:text-[15px] max-[760px]:[&_[data-ui~=lead]]:text-[14px]",
        if(@variant == "assignment",
          do: "contents [&>div:first-child]:col-start-1 [&>div:first-child]:row-start-1",
          else:
            "flex items-center justify-between gap-[28px] max-[760px]:flex-col max-[760px]:items-start"
        ),
        if(@variant in ~w(assignment student),
          do: "[&_h1]:text-[30px] [&_h1]:tracking-[-.85px] max-[760px]:[&_h1]:text-[27px]",
          else:
            "[&_h1]:mb-[12px] [&_h1]:text-[34px] [&_h1]:tracking-[-1.05px] max-[760px]:[&_h1]:text-[29px]"
        ),
        @variant in ~w(default admin) && "max-[760px]:gap-[22px]",
        @variant in ~w(default classroom) && "mb-[38px] max-[760px]:mb-[28px]",
        @variant == "classroom" && "max-[760px]:gap-[16px]",
        @variant == "assignment" && "[&_h1]:mb-0",
        @variant == "student" && "[&_h1]:mb-[12px]",
        @variant == "student" && "max-[760px]:items-stretch max-[760px]:gap-[20px]",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :kind, :string, default: "student", values: ~w(student institution assignment)
  slot :inner_block, required: true

  def overview(assigns) do
    ~H"""
    <div
      data-ui={
        case @kind do
          "institution" -> "admin-overview"
          "assignment" -> "assignment-overview"
          _ -> "student-overview"
        end
      }
      class={[
        "mb-[22px] rounded-[16px] border border-panel bg-white px-[30px] py-[28px] shadow-overview max-[1000px]:p-[24px] max-[760px]:px-[20px] max-[760px]:py-[22px]",
        @kind == "assignment" &&
          "relative grid grid-cols-[minmax(0,1fr)_max-content] gap-y-0 gap-x-[28px] max-[1000px]:gap-x-[20px] max-[760px]:flex max-[760px]:flex-col max-[760px]:gap-x-0",
        @kind == "student" &&
          "[&_[data-ui~=assignment-facts]]:mt-[24px] [&_[data-ui~=assignment-facts]]:border-t [&_[data-ui~=assignment-facts]]:border-line [&_[data-ui~=assignment-facts]]:pt-[20px] max-[760px]:[&_[data-variant=primary]]:justify-center",
        @kind == "institution" &&
          "[&_dl]:mt-[24px] [&_dl]:mb-0 [&_dl]:border-t [&_dl]:border-line [&_dl]:pt-[22px] max-[760px]:[&_dl]:flex-wrap max-[760px]:[&_dl]:justify-between max-[760px]:[&_dl]:gap-[12px]"
      ]}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :variant, :string, default: "default", values: ~w(default account)
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def panel(assigns) do
    ~H"""
    <section
      data-ui={if @variant == "account", do: "settings-panel", else: "admin-panel"}
      class={[
        "rounded-[12px] border border-panel bg-white shadow-panel",
        if(@variant == "account",
          do:
            "[&_strong]:block [&_strong]:wrap-anywhere [&_strong]:text-[14px] [&_strong]:font-[550]",
          else: "mb-[22px] overflow-hidden [&_h2]:text-[16px] [&_h2]:font-semibold"
        ),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :variant, :string, default: "default", values: ~w(default account)
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def panel_heading(assigns) do
    ~H"""
    <div
      data-ui={if @variant == "account", do: "settings-panel-heading", else: "admin-panel-heading"}
      class={[
        "border-b border-line p-[22px] [&_p]:text-[13px] [&_p]:text-muted max-[760px]:p-[18px]",
        if(@variant == "account",
          do: "[&_h2]:text-[15px] [&_h2]:font-semibold [&_p]:mt-[8px] [&_p]:leading-[1.65]",
          else:
            "flex items-start gap-[14px] bg-surface-heading [&>.hero-server-stack]:mt-[3px] [&>.hero-server-stack]:shrink-0 [&>.hero-server-stack]:text-brand [&>.hero-key]:mt-[3px] [&>.hero-key]:shrink-0 [&>.hero-key]:text-brand [&>.hero-building-library]:mt-[3px] [&>.hero-building-library]:shrink-0 [&>.hero-building-library]:text-brand [&_p]:mt-[6px] [&_p]:leading-[1.6] [&_[data-ui~=admin-tag]]:ml-auto max-[760px]:flex-wrap max-[760px]:[&>div]:flex-1"
        ),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def form_section(assigns) do
    ~H"""
    <section
      class={[
        "mb-[20px] rounded-[10px] border border-subtle bg-white px-[24px] pt-[24px] pb-[8px] [&>h2]:mb-[22px] [&>h2]:text-[16px] [&>h2]:font-semibold [&>[data-ui~=field-help]]:-mt-[10px] max-[600px]:px-[16px] max-[600px]:pt-[18px] max-[600px]:pb-[2px]",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def list_toolbar(assigns) do
    ~H"""
    <div
      data-ui="toolbar"
      class={[
        "mt-[28px] mb-[21px] flex items-center justify-between gap-[16px] [&_h2]:text-[15px] [&_h2]:font-semibold [&_.ui-search]:w-[280px] [&_.ui-search]:max-w-full max-[760px]:mt-[22px] max-[760px]:mb-[16px] max-[760px]:flex-wrap max-[760px]:[&>form]:order-2 max-[760px]:[&>form]:w-full max-[760px]:has-[form]:justify-end",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def empty_state(assigns) do
    ~H"""
    <div
      data-ui="empty"
      class={[
        "flex min-h-[240px] flex-col items-center justify-center gap-[12px] rounded-[9px] border border-dashed border-[#d9e0eb] bg-white px-[24px] py-[36px] text-center text-[#6a768a] [&_h2]:text-[17px] [&_h2]:font-semibold [&_h2]:text-ink [&_h3]:text-[17px] [&_h3]:font-semibold [&_h3]:text-ink [&_p]:max-w-[390px]",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def modal_actions(assigns) do
    ~H"""
    <div
      data-ui="modal-actions"
      class={[
        "mt-[12px] flex flex-wrap justify-end gap-[10px] [&>a]:max-w-full [&>button]:max-w-full max-[480px]:flex-col-reverse",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def assignment_facts(assigns) do
    ~H"""
    <div
      data-ui="assignment-facts"
      class={[
        "[&>span[data-team]]:flex-wrap [&>span[data-team]]:gap-x-[10px] [&>span[data-team]]:gap-y-[4px]",
        "col-start-1 row-start-2 mt-[18px] flex flex-wrap gap-x-[20px] gap-y-[12px] text-[12px] text-muted [&>span]:inline-flex [&>span]:items-center [&>span]:gap-[8px] max-[760px]:order-1 max-[760px]:flex-col max-[760px]:gap-[12px]",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def classroom_meta(assigns) do
    ~H"""
    <div
      data-ui="class-meta"
      class={[
        "mb-[32px] flex flex-wrap gap-x-[30px] gap-y-[12px] text-[12px] text-muted [&>span]:inline-flex [&>span]:items-center [&>span]:gap-[8px] max-[760px]:mb-[22px] max-[760px]:flex-col max-[760px]:items-start max-[760px]:gap-[8px]",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def eyebrow(assigns) do
    ~H"""
    <p data-ui="context" class={[" text-brand text-[13px] font-semibold m-0", @class]} {@rest}>
      {render_slot(@inner_block)}
    </p>
    """
  end

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def lead(assigns) do
    ~H"""
    <p
      data-ui="lead"
      class={[
        "text-muted text-[14px] leading-[1.65] max-w-[620px] wrap-anywhere m-0",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </p>
    """
  end

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def field_hint(assigns) do
    ~H"""
    <p
      data-ui="field-help"
      class={["text-muted text-[12px] leading-[1.7] mt-[-8px] mb-[20px] mx-0", @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </p>
    """
  end

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span
      data-ui="admin-tag"
      class={[
        "inline-flex items-center text-[11px] font-medium text-secondary bg-soft rounded-[5px] whitespace-nowrap py-[4px] px-[8px]",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

  attr :kind, :string, default: "success", values: ~w(success error)
  attr :icon, :string, default: nil
  attr :role, :string, default: nil
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def notice(assigns) do
    ~H"""
    <p
      data-ui={if @kind == "error", do: "error", else: "notice"}
      role={@role || if(@kind == "error", do: "alert", else: "status")}
      class={[
        if(@kind == "error",
          do: "mb-[24px] rounded-[6px] bg-error-surface px-[16px] py-[12px] text-error!",
          else: "mt-[20px] rounded-[6px] bg-success-surface px-[16px] py-[12px] text-success-ink"
        ),
        @icon && "flex items-start gap-[10px] rounded-[8px]",
        @class
      ]}
      {@rest}
    >
      <GradePushWeb.CoreComponents.icon :if={@icon} name={@icon} class="mt-[1px] size-5 shrink-0" />
      <span :if={@icon} class="min-w-0 flex-1">{render_slot(@inner_block)}</span>
      <%= if !@icon do %>
        {render_slot(@inner_block)}
      <% end %>
    </p>
    """
  end
end
