defmodule GradePushWeb.ClassroomComponents do
  @moduledoc false
  use GradePushWeb, :html

  attr :classes, :list, required: true
  slot :inner_block, required: true

  def grouped_classes(assigns) do
    assigns =
      assign(assigns, :groups, GradePushWeb.Presentation.classroom_groups(assigns.classes))

    ~H"""
    <section
      :for={{group, index} <- Enum.with_index(@groups)}
      data-ui="term-group"
      class="mt-[38px] [&+[data-ui~=term-group]]:mt-[36px]"
      aria-labelledby={"term-#{index}"}
    >
      <div class={[
        "mb-[16px] flex items-center justify-between gap-[16px]",
        "after:order-1 after:h-px after:flex-1 after:bg-divider after:content-[''] max-[760px]:after:hidden"
      ]}>
        <h2
          id={"term-#{index}"}
          class="flex min-w-0 items-center gap-[8px] wrap-anywhere text-[14px] font-semibold"
        >
          <.icon name="hero-calendar-days" class="size-4 shrink-0" />{group.label}
        </h2>
        <span class="order-2 shrink-0 text-[12px] text-muted">
          {ngettext("%{count} classroom", "%{count} classrooms", length(group.classes))}
        </span>
      </div>
      <div class="grid grid-cols-3 gap-[22px] max-[760px]:grid-cols-1">
        <%= for classroom <- group.classes do %>
          {render_slot(@inner_block, classroom)}
        <% end %>
      </div>
    </section>
    """
  end

  attr :path, :string, required: true
  attr :title, :string, required: true
  attr :code, :string, default: nil
  attr :description, :string, default: nil
  attr :students, :integer, default: nil
  attr :assignments, :integer, required: true
  attr :teachers, :list, required: true

  def card(assigns) do
    ~H"""
    <.link
      patch={@path}
      data-ui="class-card"
      class={[
        "relative flex flex-col rounded-[16px] border border-panel bg-white px-[26px] pt-[26px] shadow-classroom",
        "transition-[border-color,box-shadow] duration-150 hover:border-brand-outline hover:shadow-classroom-hover max-[760px]:px-[22px] max-[760px]:pt-[24px]",
        "before:absolute before:-top-px before:left-[26px] before:h-[4px] before:w-[30px] before:rounded-b-[4px] before:bg-brand before:content-['']"
      ]}
    >
      <div class="mb-[28px] flex items-center justify-between text-faint">
        <span class="rounded-[5px] bg-brand-soft px-[8px] py-[5px] text-[11px] font-[650] tracking-[.4px] text-brand-strong">
          {if @code in [nil, ""], do: gettext("Classroom"), else: @code}
        </span>
        <.icon name="hero-arrow-up-right" class="size-[18px]" />
      </div>
      <h3 class="mt-[10px] mb-[12px] wrap-anywhere text-[23px] leading-[1.25] font-semibold tracking-[-.55px]">
        {@title}
      </h3>
      <p
        :if={@description not in [nil, ""]}
        class="mb-[22px] min-h-[50px] wrap-anywhere text-[14px] leading-[1.65] text-muted"
      >
        {@description}
      </p>
      <div data-ui="card-counts" class="mt-auto flex gap-[22px] pb-[24px] text-[12px] text-card-meta">
        <span :if={@students} class="flex items-center gap-[7px]">
          <.icon name="hero-user-group" class="size-4 text-brand" />{ngettext(
            "%{count} student",
            "%{count} students",
            @students
          )}
        </span>
        <span class="flex items-center gap-[7px]">
          <.icon name="hero-document-text" class="size-4 text-brand" />{ngettext(
            "%{count} assignment",
            "%{count} assignments",
            @assignments
          )}
        </span>
      </div>
      <div
        data-ui="card-teachers"
        class={[
          "-mx-[26px] flex min-h-[60px] items-center gap-[9px] rounded-b-[16px] border-t border-card-divider bg-surface-heading px-[26px] py-[18px]",
          "max-[1000px]:items-start max-[760px]:-mx-[22px] max-[760px]:items-center max-[760px]:px-[22px] max-[760px]:py-[17px]"
        ]}
      >
        <div class="flex shrink-0 pr-[3px]" aria-hidden="true">
          <.user_avatar
            :for={teacher <- @teachers}
            src={Map.get(teacher, :avatar_url)}
            size="small"
            class="-mr-[5px] border-2 border-white"
          >
            {teacher.initials}
          </.user_avatar>
        </div>
        <span class="min-w-0 wrap-anywhere text-[11px] leading-[1.5] text-muted">{Enum.map_join(
          @teachers,
          ", ",
          & &1.name
        )}</span>
      </div>
    </.link>
    """
  end

  attr :items, :list, required: true

  def breadcrumbs(assigns) do
    ~H"""
    <nav
      data-ui="breadcrumbs"
      class="mb-[22px] text-[12px] text-muted"
      aria-label={gettext("Breadcrumb")}
    >
      <ol class="flex flex-wrap items-center gap-x-0 gap-y-[4px]">
        <li
          :for={{label, path} <- @items}
          class={[
            "flex min-w-0 items-baseline",
            "[&+li]:before:shrink-0 [&+li]:before:px-[10px] [&+li]:before:text-faint [&+li]:before:content-['/']"
          ]}
        >
          <.link
            :if={path}
            patch={path}
            class="wrap-anywhere py-[6px] underline-offset-[3px] hover:text-brand hover:underline"
          >{label}</.link>
          <span :if={is_nil(path)} class="wrap-anywhere py-[6px] text-heading" aria-current="page">{label}</span>
        </li>
      </ol>
    </nav>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :url, :string, required: true
  attr :status, :string, default: nil
  attr :disabled, :boolean, default: false

  def invitation_link(assigns) do
    ~H"""
    <div class="grid text-[13px] font-[550] mt-[22px] gap-[7px]">
      <.field for={@id <> "-input"}>{@label}</.field><div class="flex items-stretch gap-[8px]">
        <.input
          id={@id <> "-input"}
          readonly
          value={@url}
          disabled={@disabled}
          placeholder={if @disabled, do: gettext("Unavailable in demo mode")}
        /><.button
          type="button"
          id={@id <> "-copy"}
          phx-hook="CopyInvitation"
          data-copy={@url}
          disabled={@disabled}
          variant="copy"
          aria-label={gettext("Copy invitation link")}
          title={gettext("Copy invitation link")}
        ><.icon name="hero-document-duplicate" class="size-5" /></.button>
      </div><span
        class="text-[#596b80] text-[12px] font-normal min-h-[18px]"
        role="status"
      >{@status}</span>
    </div>
    """
  end
end
