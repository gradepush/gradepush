defmodule GradePushWeb.ClipboardComponents do
  @moduledoc "Copyable text with consistent clipboard controls and feedback."
  use GradePushWeb, :html

  attr :id, :string, required: true
  attr :value, :string, required: true
  attr :label, :string, required: true
  attr :disabled, :boolean, default: false

  def copy_field(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="CopyToClipboard"
      data-copy={@value}
      data-success={gettext("Copied")}
      data-error={gettext("Copy failed. Select and copy the text manually.")}
      class="relative"
    >
      <div class={[
        "flex items-center gap-[10px] rounded-[7px] border border-line bg-surface-heading px-[12px] py-[8px]",
        @disabled && "opacity-60"
      ]}>
        <pre
          :if={!@disabled}
          tabindex="0"
          role="region"
          aria-label={@label}
          class="min-w-0 flex-1 overflow-x-auto rounded-[3px] py-[4px] text-[12px] leading-[20px] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand"
        ><code class="block w-max select-all whitespace-pre">{@value}</code></pre>
        <span :if={@disabled} class="min-w-0 flex-1 text-[12px] text-muted">
          {gettext("Unavailable in demo mode")}
        </span>
        <.button
          id={@id <> "-copy"}
          variant="copy"
          class="h-[32px] shrink-0"
          disabled={@disabled}
          aria-label={@label}
          title={@label}
        >
          <span data-copy-icon aria-hidden="true"><.icon
            name="hero-document-duplicate"
            class="size-4"
          /></span>
          <span data-copy-success-icon hidden aria-hidden="true"><.icon
            name="hero-check"
            class="size-4 text-[#187044]"
          /></span>
          <span data-copy-error-icon hidden aria-hidden="true"><.icon
            name="hero-exclamation-circle"
            class="size-4 text-danger"
          /></span>
        </.button>
      </div>
      <span
        data-copy-tooltip
        hidden
        aria-hidden="true"
        class="pointer-events-none absolute right-[8px] bottom-[calc(100%+6px)] z-10 max-w-full rounded-md bg-heading px-[10px] py-[6px] text-[12px] font-medium leading-[1.5] text-white shadow-md"
      ></span>
      <span role="status" aria-atomic="true" class="sr-only"></span>
    </div>
    """
  end
end
