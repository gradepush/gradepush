defmodule GradePushWeb.CoreComponents do
  @moduledoc "Shared controls with consistent styling, labels, and validation states."
  use Phoenix.Component
  use Gettext, backend: GradePushWeb.Gettext

  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  attr :src, :string, default: nil
  attr :size, :string, default: "default", values: ~w(default small)
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block

  def user_avatar(assigns) do
    assigns =
      assign(assigns, :classes, [
        "inline-flex max-w-none shrink-0 items-center justify-center rounded-full object-cover font-semibold",
        if(assigns.size == "small",
          do: "size-[29px] bg-avatar-small text-[10px] text-avatar-ink",
          else: "size-[34px] bg-avatar text-[12px] text-secondary"
        ),
        assigns.class
      ])

    ~H"""
    <img :if={@src} src={@src} alt="" data-avatar class={@classes} {@rest} />
    <span :if={!@src} data-avatar class={@classes} {@rest}>{render_slot(@inner_block)}</span>
    """
  end

  attr :icon, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def connection_status(assigns) do
    ~H"""
    <span
      data-ui="connection-state"
      class={[
        "ml-auto inline-flex items-center gap-[6px] whitespace-nowrap text-[11px] text-connection max-[760px]:ml-[50px]",
        @class
      ]}
    >
      <.icon :if={@icon} name={@icon} class="size-[16px]" />
      <span :if={!@icon} class="size-[6px] rounded-full bg-connection-dot" aria-hidden="true"></span>
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc "Renders an action or navigation link with a shared visual variant."
  attr :variant, :string,
    default: "secondary",
    values: ~w(secondary primary danger text text-danger icon ghost link copy)

  attr :size, :string, default: "default", values: ~w(default compact small)
  attr :compact_on_mobile, :boolean, default: false
  attr :type, :string, default: "button", values: ~w(button submit reset)
  attr :class, :any, default: nil

  attr :rest, :global,
    include: ~w(href navigate patch method download name value disabled form target rel)

  slot :inner_block, required: true

  def button(assigns) do
    assigns =
      assign(assigns, :classes, [
        button_classes(assigns.variant, assigns.size, assigns.compact_on_mobile),
        assigns.class
      ])

    ~H"""
    <.link
      :if={@rest[:href] || @rest[:navigate] || @rest[:patch]}
      data-variant={@variant}
      class={@classes}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    <button
      :if={!(@rest[:href] || @rest[:navigate] || @rest[:patch])}
      type={@type}
      data-variant={@variant}
      class={@classes}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp button_classes(variant, size, compact_on_mobile) do
    [
      "inline-flex shrink-0 items-center justify-center disabled:cursor-not-allowed",
      variant != "primary" && "disabled:opacity-50",
      button_variant(variant),
      if(variant == "link", do: "font-normal", else: "font-[550]"),
      variant in ~w(primary secondary danger) && "gap-[8px] rounded-[9px] border",
      variant in ~w(primary secondary danger) && button_size(size),
      compact_on_mobile && "max-[760px]:px-[8px] max-[760px]:py-[9px] max-[760px]:text-[12px]"
    ]
  end

  defp button_variant("primary"),
    do:
      "border-brand bg-brand text-white shadow-button hover:border-brand-hover hover:bg-brand-hover disabled:opacity-100 disabled:border-[#e4e8f0] disabled:bg-[#edf0f6] disabled:text-[#6a7485]"

  defp button_variant("secondary"),
    do: "border-[#dce1e9] bg-white text-ink hover:border-[#c5ccd8] hover:bg-[#f6f8fb]"

  defp button_variant("danger"),
    do: "border-danger bg-danger text-white hover:border-danger-hover hover:bg-danger-hover"

  defp button_variant("text"),
    do: "min-h-[40px] gap-1.5 py-[9px] text-[12px] text-brand"

  defp button_variant("text-danger"),
    do: "min-h-[40px] gap-1.5 py-[9px] text-[12px] text-danger"

  defp button_variant("icon"),
    do:
      "size-[32px] rounded-[5px] border-0 bg-transparent p-[7px] text-[#67758a] hover:bg-[#f3f5f9] hover:text-danger"

  defp button_variant("ghost"),
    do:
      "size-[40px] rounded-[7px] border-0 bg-transparent text-muted hover:bg-[#edf2fa] hover:text-ink"

  defp button_variant("link"),
    do: "text-[12px] text-muted underline-offset-[3px] hover:text-brand hover:underline"

  defp button_variant("copy"),
    do:
      "w-[42px] rounded-[6px] border border-[#d7dfeb] bg-white text-[#536580] hover:border-brand hover:text-brand"

  defp button_size("default"), do: "min-h-[42px] px-[15px] py-[10px] text-[13px]"
  defp button_size("compact"), do: "min-h-[36px] px-[10px] py-[7px] text-[12px]"

  defp button_size("small"), do: "min-h-[40px] px-[12px] py-[8px] text-[12px]"

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def data_list(assigns) do
    ~H"""
    <div
      class={[
        "overflow-hidden rounded-[12px] border border-line bg-white shadow-panel [&>[data-list-row]+[data-list-row]]:border-t",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(for)
  slot :inner_block, required: true

  def field(assigns) do
    ~H"""
    <label class={["grid min-w-0 gap-[7px] text-[13px] font-[550] text-[#354157]", @class]} {@rest}>{render_slot(
      @inner_block
    )}</label>
    """
  end

  @doc "Renders a field or a standalone control. Explicit option slots support conditional select options."
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values:
      ~w(checkbox color date datetime-local email file month number password search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField, default: nil
  attr :errors, :list, default: []
  attr :wrap, :boolean, default: false
  attr :checked, :boolean
  attr :prompt, :string, default: nil
  attr :options, :list, default: []
  attr :multiple, :boolean, default: false
  attr :class, :any, default: nil

  attr :rest, :global,
    include:
      ~w(accept autocomplete capture cols disabled form list max maxlength min minlength pattern placeholder readonly required rows size step)

  slot :inner_block

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(
      field: nil,
      wrap: true,
      id: assigns.id || field.id
    )
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> assign(:errors, Enum.map(errors, &translate_error/1))
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    assigns = assigns |> assign_new(:name, fn -> nil end) |> assign_new(:value, fn -> nil end)

    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(assigns) do
    assigns =
      assigns
      |> assign_new(:name, fn -> nil end)
      |> assign_new(:value, fn -> nil end)
      |> assign_new_control_id()
      |> input_error_attributes()
      |> assign_new(:checked, fn -> Form.normalize_value("checkbox", Map.get(assigns, :value)) end)

    ~H"""
    <div :if={@label || @errors != [] || @wrap} id={@id && "#{@id}-field"} class="ui-field min-w-0">
      <label
        :if={@label && @type != "checkbox"}
        for={@id}
        class="mb-[7px] block text-[13px] font-[550] text-[#354157]"
      >{@label}</label>
      <.control {assigns} />
      <.input_errors id={@id} errors={@errors} />
    </div>
    <.control :if={!(@label || @errors != [] || @wrap)} {assigns} />
    """
  end

  defp control(%{type: "checkbox"} = assigns) do
    ~H"""
    <label class="flex items-center gap-2 text-[13px] font-[550] text-[#354157] has-[:disabled]:text-muted">
      <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} form={@rest[:form]} />
      <input
        type="checkbox"
        id={@id}
        name={@name}
        value="true"
        checked={@checked}
        class={["size-[17px] shrink-0 accent-brand disabled:opacity-50", @class]}
        {@rest}
      />
      {@label}
    </label>
    """
  end

  defp control(%{type: "select"} = assigns) do
    ~H"""
    <select
      id={@id}
      name={@name}
      multiple={@multiple}
      class={[control_classes(), "ui-select", @class]}
      {@rest}
    >
      <option :if={@prompt} value="">{@prompt}</option>
      {Phoenix.HTML.Form.options_for_select(@options, @value)}
      {render_slot(@inner_block)}
    </select>
    """
  end

  defp control(%{type: "textarea"} = assigns) do
    ~H"""
    <textarea
      id={@id}
      name={@name}
      class={[control_classes(), "resize-y leading-[1.65]", @class]}
      {@rest}
    >{Form.normalize_value("textarea", @value)}</textarea>
    """
  end

  defp control(assigns) do
    ~H"""
    <input
      type={@type}
      id={@id}
      name={@name}
      value={Form.normalize_value(@type, @value)}
      class={[control_classes(), @class]}
      {@rest}
    />
    """
  end

  defp assign_new_control_id(assigns) do
    needs_id? = assigns.label || assigns.errors != []
    id = assigns.id || (needs_id? && assigns.name && control_id(assigns.name))
    assign(assigns, :id, id || nil)
  end

  defp control_id(name), do: name |> String.replace(~r/[\[\]]+/, "_") |> String.trim_trailing("_")

  defp control_classes do
    "ui-control min-h-[44px] w-full min-w-0 rounded-[7px] border border-control bg-white px-[12px] py-[10px] text-[14px] font-normal text-ink focus:border-brand [&[readonly]]:bg-[#f8f9fc] [&[readonly]]:text-muted disabled:bg-[#f5f7fa] disabled:text-muted aria-[invalid=true]:border-danger"
  end

  attr :id, :string, required: true
  attr :name, :string, default: "query"
  attr :label, :string, required: true
  attr :value, :string, default: ""
  attr :rest, :global, include: ~w(placeholder maxlength)

  def search_input(assigns) do
    ~H"""
    <label
      for={@id}
      class={[
        "ui-search flex min-h-[44px] min-w-0 items-center gap-2 rounded-[7px] border border-control bg-white",
        "px-[12px] text-muted focus-within:border-brand focus-within:outline-2 focus-within:outline-offset-2",
        "focus-within:outline-brand"
      ]}
    >
      <.icon name="hero-magnifying-glass" class="size-4" />
      <span class="sr-only">{@label}</span>
      <input
        id={@id}
        name={@name}
        type="search"
        value={@value}
        class="min-w-0 w-full border-0 bg-transparent py-[10px] text-ink focus:outline-none"
        {@rest}
      />
    </label>
    """
  end

  attr :id, :string, required: true
  attr :dialog_id, :string, required: true
  attr :title_id, :string, required: true
  attr :title, :string, required: true
  attr :close_id, :string, default: nil
  attr :initial_focus, :any, default: JS.focus_first()
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      class="fixed inset-0 z-[60] flex items-center justify-center overflow-y-auto bg-[#17233850] p-[24px] max-[760px]:p-[16px]"
      phx-window-keydown="close"
      phx-key="Escape"
      phx-remove={JS.pop_focus()}
    >
      <.focus_wrap
        id={@dialog_id}
        class={[
          "w-[480px] max-w-full max-h-[calc(100dvh-48px)] overflow-auto rounded-xl bg-white p-[28px] shadow-[0_20px_80px_#14203930] [&>p]:text-muted [&>p]:leading-[1.65] max-[760px]:max-h-[calc(100dvh-32px)] max-[760px]:p-[22px]",
          @class
        ]}
        role="dialog"
        aria-modal="true"
        aria-labelledby={@title_id}
        phx-mounted={@initial_focus}
      >
        <div data-ui="modal-heading" class="mb-[22px] flex items-center justify-between gap-4">
          <h2 id={@title_id} tabindex="-1" class="text-[20px] font-semibold tracking-[-.3px]">
            {@title}
          </h2>
          <.button variant="icon" id={@close_id} phx-click="close" aria-label={gettext("Close")}><.icon
            name="hero-x-mark"
            class="size-5"
          /></.button>
        </div>
        {render_slot(@inner_block)}
      </.focus_wrap>
    </div>
    """
  end

  defp input_error_attributes(assigns) do
    if assigns.errors == [] do
      assigns
    else
      description =
        [assigns.rest[:"aria-describedby"], input_error_id(assigns.id)]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" ")

      assign(
        assigns,
        :rest,
        Map.merge(assigns.rest, %{"aria-invalid": "true", "aria-describedby": description})
      )
    end
  end

  defp input_error_id(nil), do: nil
  defp input_error_id(id), do: "#{id}-errors"

  defp input_errors(assigns) do
    ~H"""
    <div :if={@errors != []} id={input_error_id(@id)}>
      <p :for={msg <- @errors} class="mt-1.5 flex items-center gap-2 text-[12px] text-danger">
        <.icon name="hero-exclamation-circle" class="size-5" />{msg}
      </p>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "github"} = assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" class={@class} fill="currentColor" aria-hidden="true">
      <path d="M12 .297a12 12 0 0 0-3.793 23.384c.6.111.82-.261.82-.577v-2.234c-3.338.726-4.043-1.416-4.043-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.09-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.071 1.835 2.809 1.305 3.495.998.108-.776.419-1.305.762-1.605-2.665-.305-5.467-1.334-5.467-5.931 0-1.31.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.323 3.301 1.23a11.52 11.52 0 0 1 6.006 0c2.291-1.553 3.297-1.23 3.297-1.23.653 1.652.242 2.873.119 3.176.769.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.216.694.825.576A12 12 0 0 0 12 .297Z" />
    </svg>
    """
  end

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} aria-hidden="true" />
    """
  end

  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(GradePushWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(GradePushWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
