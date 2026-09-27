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
      class="cp-term-group"
      aria-labelledby={"term-#{index}"}
    >
      <div class="cp-section-label">
        <h2 id={"term-#{index}"}><.icon name="hero-calendar-days" class="size-4" />{group.label}</h2>
        <span>{ngettext("%{count} classroom", "%{count} classrooms", length(group.classes))}</span>
      </div>
      <div class="cp-grid">
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
    <.link patch={@path} class="cp-class-card">
      <div class="cp-card-top">
        <span class="cp-course-code">{if @code in [nil, ""], do: gettext("Classroom"), else: @code}</span><.icon
          name="hero-arrow-up-right"
          class="size-4"
        />
      </div>
      <h3>{@title}</h3>
      <p :if={@description not in [nil, ""]} class="cp-card-description">{@description}</p>
      <div class="cp-card-counts">
        <span :if={@students}><.icon name="hero-user-group" class="size-4" />{ngettext(
          "%{count} student",
          "%{count} students",
          @students
        )}</span>
        <span><.icon name="hero-document-text" class="size-4" />{ngettext(
          "%{count} assignment",
          "%{count} assignments",
          @assignments
        )}</span>
      </div>
      <div class="cp-card-teachers">
        <div class="cp-avatar-stack" aria-hidden="true">
          <span :for={teacher <- @teachers} class="cp-small-avatar">{teacher.initials}</span>
        </div>
        <span>{Enum.map_join(@teachers, ", ", & &1.name)}</span>
      </div>
    </.link>
    """
  end

  attr :items, :list, required: true

  def breadcrumbs(assigns) do
    ~H"""
    <nav class="cp-breadcrumbs" aria-label={gettext("Breadcrumb")}>
      <ol>
        <li :for={{label, path} <- @items}>
          <.link :if={path} patch={path}>{label}</.link>
          <span :if={is_nil(path)} aria-current="page">{label}</span>
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
    <div class="cp-link-field">
      <.field for={@id <> "-input"}>{@label}</.field><div class="cp-copy-field">
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
      </div><span class="cp-copy-status" role="status">{@status}</span>
    </div>
    """
  end
end
