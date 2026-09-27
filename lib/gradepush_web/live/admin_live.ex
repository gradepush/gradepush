defmodule GradePushWeb.AdminLive do
  @moduledoc "Administration UI preview with local sample state, without authentication or external operations."
  use GradePushWeb, :live_view

  alias GradePushWeb.AdminComponents
  alias GradePushWeb.ClassroomComponents
  alias GradePushWeb.Preview.Administration
  alias GradePushWeb.Preview.Fixtures
  alias GradePushWeb.Preview.Platform
  alias GradePushWeb.WorkspaceLayout

  @impl true
  def mount(_params, session, socket) do
    locale = if session["locale"] in ~w(en fr), do: session["locale"], else: "en"
    Gettext.put_locale(GradePushWeb.Gettext, locale)
    user = hd(Fixtures.teachers())

    {:ok,
     assign(socket,
       locale: locale,
       user: user,
       platform: Platform.for_user(user),
       actor_id: "jordan",
       state: Administration.initial(),
       section: "teachers",
       modal: nil,
       error: nil,
       notice: nil,
       query: "",
       copy_status: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    sections =
      if socket.assigns.live_action == :institution,
        do: ~w(teachers classrooms history settings),
        else: ~w(configuration services history)

    section = if params["section"] in sections, do: params["section"], else: hd(sections)

    title =
      if socket.assigns.live_action == :institution,
        do: gettext("Institution"),
        else: gettext("Platform")

    {:noreply,
     assign(socket,
       section: section,
       page_title: title,
       modal: nil,
       notice: nil,
       error: nil,
       query: ""
     )}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket),
    do: {:noreply, assign(socket, query: query)}

  def handle_event("open_admin", %{"kind" => kind} = params, socket)
      when kind in ~w(invite member staff) do
    {:noreply, assign(socket, modal: {kind, params["id"]}, error: nil, copy_status: nil)}
  end

  def handle_event("close", _, socket), do: {:noreply, assign(socket, modal: nil, error: nil)}

  def handle_event("invitation_copied", %{"ok" => ok}, socket) do
    text =
      if ok,
        do: gettext("Link copied"),
        else: gettext("Copy failed. Select and copy the link manually.")

    {:noreply, assign(socket, copy_status: text)}
  end

  def handle_event("save_staff", %{"staff" => params}, socket) do
    {"staff", id} = socket.assigns.modal

    result =
      Administration.change_staff(socket.assigns.state, socket.assigns.actor_id, id, params)

    complete(socket, result)
  end

  def handle_event("save_role", %{"member" => %{"role" => role}}, socket) do
    {"member", id} = socket.assigns.modal

    complete(
      socket,
      Administration.change_role(socket.assigns.state, socket.assigns.actor_id, id, role)
    )
  end

  def handle_event("confirm_remove", _, socket) do
    {"member", id} = socket.assigns.modal
    {:noreply, assign(socket, modal: {"remove", id}, error: nil)}
  end

  def handle_event("remove_member", _, socket) do
    {"remove", id} = socket.assigns.modal

    complete(
      socket,
      Administration.remove_teacher(socket.assigns.state, socket.assigns.actor_id, id)
    )
  end

  def handle_event("save_institution", %{"institution" => %{"name" => name}}, socket) do
    complete(socket, Administration.rename(socket.assigns.state, socket.assigns.actor_id, name))
  end

  defp complete(socket, {:ok, state}),
    do:
      {:noreply,
       assign(socket,
         state: state,
         modal: nil,
         error: nil,
         notice: gettext("Changes saved in this preview.")
       )}

  defp complete(socket, {:error, message}), do: {:noreply, assign(socket, error: message)}

  defp visible(records, query),
    do:
      Enum.filter(
        records,
        &String.contains?(String.downcase(&1.name <> " " <> &1.handle), String.downcase(query))
      )

  defp local(text, locale), do: Map.fetch!(text, String.to_existing_atom(locale))

  defp open_modal(kind, id \\ nil),
    do: JS.push_focus() |> JS.push("open_admin", value: %{kind: kind, id: id})

  defp base(:institution), do: "/admin/institution"
  defp base(:platform), do: "/admin/platform"

  defp language_url(action, section, locale),
    do: base(action) <> "?" <> URI.encode_query(%{section: section, locale: locale})

  defp modal_title({"invite", _}), do: gettext("Invite a teacher")
  defp modal_title({"member", _}), do: gettext("Manage teacher")
  defp modal_title({"remove", _}), do: gettext("Remove teacher?")
  defp modal_title({"staff", _}), do: gettext("Assign teachers")
end
