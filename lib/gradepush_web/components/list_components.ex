defmodule GradePushWeb.ListComponents do
  @moduledoc "Consistent headers, rows, and responsive tables for workspace lists."
  use Phoenix.Component

  attr :kind, :string,
    default: "assignments",
    values: ~w(assignments student_assignments students table)

  slot :inner_block, required: true

  def list_header(assigns) do
    ~H"""
    <.dynamic_tag
      tag_name={if @kind == "table", do: "thead", else: "div"}
      data-ui={if @kind == "students", do: "student-labels", else: "assignment-labels"}
      class={[
        "border-b border-list-divider bg-surface-heading text-[12px] font-semibold tracking-[.1px] text-heading",
        @kind != "table" && "px-[20px] py-[16px] max-[760px]:hidden",
        columns(@kind)
      ]}
    >
      {render_slot(@inner_block)}
    </.dynamic_tag>
    """
  end

  attr :kind, :string,
    default: "assignments",
    values: ~w(assignments student_assignments students)

  attr :rest, :global, include: ~w(patch navigate href)
  slot :inner_block, required: true

  def list_row(assigns) do
    assigns =
      assign(
        assigns,
        :link?,
        !!(assigns.rest[:patch] || assigns.rest[:navigate] || assigns.rest[:href])
      )

    ~H"""
    <.link
      :if={@link?}
      data-ui={if @kind == "students", do: "student", else: "assignment"}
      data-list-row
      class={row_classes(@kind)}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    <div
      :if={!@link?}
      data-ui={if @kind == "students", do: "student", else: "assignment"}
      data-list-row
      class={row_classes(@kind)}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp row_classes(kind) do
    [
      "border-line px-[20px] py-[22px] hover:bg-surface-hover focus-visible:outline-offset-[-3px] max-[760px]:px-[18px] max-[760px]:py-[20px] max-[760px]:first-of-type:border-t-0",
      columns(kind),
      if(kind == "students",
        do:
          "text-[13px] max-[760px]:grid-cols-[1fr_32px] max-[760px]:gap-x-[8px] max-[760px]:gap-y-[3px]",
        else:
          "[&_h3]:mb-[4px] [&_h3]:wrap-anywhere [&_h3]:text-[14px] [&_h3]:font-[550] [&_p]:m-0 [&_p]:text-[12px] [&_p]:text-muted hover:[&_h3]:text-brand  max-[760px]:gap-x-[8px] max-[760px]:gap-y-[16px]"
      ),
      if(kind == "student_assignments",
        do: "max-[760px]:grid-cols-2",
        else: kind == "assignments" && "max-[760px]:grid-cols-[1fr_auto]"
      )
    ]
  end

  defp columns("table"), do: nil

  defp columns("assignments"),
    do: "grid grid-cols-[minmax(0,1fr)_190px_85px] items-center gap-[24px]"

  defp columns("student_assignments"),
    do: "grid grid-cols-[minmax(0,1.3fr)_minmax(0,1fr)_minmax(0,1fr)] items-center gap-[24px]"

  defp columns("students"),
    do: "grid grid-cols-[minmax(0,1fr)_minmax(160px,.8fr)_32px] items-center gap-[16px]"

  attr :kind, :string, default: "admin", values: ~w(admin submissions)
  attr :rest, :global
  slot :inner_block, required: true

  def data_table(assigns) do
    ~H"""
    <table
      data-ui={if @kind == "admin", do: "admin-table", else: "submission-table"}
      class={[
        "w-full border-collapse text-left max-[760px]:block",
        "[&>thead_th]:px-[20px] [&>thead_th]:py-[16px] [&>thead_th]:font-semibold",
        "[&>tbody_th]:px-[20px] [&>tbody_th]:py-[22px] [&>tbody_th]:font-medium [&>tbody_td]:px-[20px] [&>tbody_td]:py-[22px]",
        "[&>tbody>tr+tr]:border-t [&>tbody>tr+tr]:border-line [&>tbody>tr]:hover:bg-surface-hover",
        "max-[760px]:[&>thead]:sr-only max-[760px]:[&>tbody]:block max-[760px]:[&>tbody>tr]:grid max-[760px]:[&>tbody>tr]:px-[18px] max-[760px]:[&>tbody>tr]:py-[20px] max-[760px]:[&>tbody>tr:first-child]:border-t-0",
        "max-[760px]:[&>thead_th]:block max-[760px]:[&>thead_th]:p-0 max-[760px]:[&>tbody_th]:block max-[760px]:[&>tbody_th]:p-0 max-[760px]:[&>tbody_td]:block max-[760px]:[&>tbody_td]:p-0",
        if(@kind == "admin",
          do:
            "text-[13px] [&_td]:text-muted [&_strong]:font-[550] max-[760px]:[&>tbody>tr]:grid-cols-[minmax(0,1fr)_auto] max-[760px]:[&>tbody>tr]:gap-x-[12px] max-[760px]:[&>tbody>tr]:gap-y-[14px] max-[760px]:[&>tbody_th]:col-span-full max-[760px]:[&_td[data-label]]:before:mb-[5px] max-[760px]:[&_td[data-label]]:before:block max-[760px]:[&_td[data-label]]:before:text-[11px] max-[760px]:[&_td[data-label]]:before:content-[attr(data-label)]",
          else:
            "text-[12px] max-[760px]:[&>tbody>tr]:grid-cols-2 max-[760px]:[&>tbody>tr]:gap-[12px] min-[761px]:max-[1000px]:[&>thead_th]:px-[10px] min-[761px]:max-[1000px]:[&>tbody_th]:px-[10px] min-[761px]:max-[1000px]:[&>tbody_td]:px-[10px]"
        )
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </table>
    """
  end

  attr :embedded, :boolean, default: false
  slot :inner_block, required: true

  def test_list(assigns) do
    ~H"""
    <ul
      data-ui="test-list"
      class={[
        "overflow-hidden bg-white [&>li]:flex [&>li]:items-start [&>li]:justify-between [&>li]:gap-[24px] [&>li]:p-[23px] [&>li+li]:border-t [&>li+li]:border-line [&_h3]:text-[14px] [&_h3]:font-semibold [&_p]:mt-[6px] [&_p]:text-[13px] [&_p]:leading-[1.65] [&_p]:text-muted [&>li>span]:whitespace-nowrap [&>li>span]:text-[13px] [&>li>span]:text-[#4e6079] [&>li>span]:tabular-nums max-[760px]:[&>li]:p-[18px] max-[760px]:[&>li]:gap-[12px]",
        if(@embedded,
          do: "rounded-b-[9px] max-[640px]:[&>li]:flex-col",
          else: "my-[24px] rounded-[9px] border border-line"
        )
      ]}
    >
      {render_slot(@inner_block)}
    </ul>
    """
  end
end
