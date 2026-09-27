defmodule GradePushWeb.ClassroomComponents do
  @moduledoc false
  use GradePushWeb, :html

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

  def invitation_link(assigns) do
    ~H"""
    <div class="cp-link-field">
      <label for={@id <> "-input"}>{@label}</label><div class="cp-copy-field">
        <input id={@id <> "-input"} readonly value={@url} /><button
          type="button"
          id={@id <> "-copy"}
          phx-hook="CopyInvitation"
          data-copy={@url}
          class="cp-copy-button"
          aria-label={gettext("Copy invitation link")}
          title={gettext("Copy invitation link")}
        ><.icon name="hero-document-duplicate" class="size-5" /></button>
      </div><span class="cp-copy-status" role="status">{@status}</span>
    </div>
    """
  end
end
