defmodule GradePushWeb.AdminLive do
  @moduledoc false
  use GradePushWeb, :live_view

  alias GradePush.Accounts
  alias GradePushWeb.{AdminComponents, AdminWorkspace, ClassroomComponents, Presentation}
  alias GradePushWeb.Preview.Administration, as: PreviewAdministration
  alias GradePushWeb.Preview.Fixtures
  alias GradePushWeb.Preview.Platform
  alias GradePushWeb.WorkspaceLayout

  @impl true
  def mount(_params, session, socket) do
    locale = if session["locale"] in ~w(en fr), do: session["locale"], else: "en"
    Gettext.put_locale(GradePushWeb.Gettext, locale)
    preview? = socket.assigns.preview?
    actor = socket.assigns.current_user
    user = if preview?, do: hd(Fixtures.teachers()), else: Presentation.user(actor)

    {:ok,
     assign(socket,
       locale: locale,
       user: user,
       platform: if(preview?, do: Platform.for_user(user), else: nil),
       actor_id: if(preview?, do: "jordan", else: to_string(actor.id)),
       state: initial_state(preview?, actor),
       contexts:
         if(preview?,
           do: [:teaching, :institution, :platform],
           else: Presentation.contexts(actor)
         ),
       invitation_url: nil,
       section: "teachers",
       modal: nil,
       error: nil,
       notice: nil,
       query: "",
       footer_form:
         to_form(Accounts.change_footer_links(socket.assigns.footer_links), as: :footer),
       copy_status: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    if allowed?(socket) do
      show_section(params, socket)
    else
      {:noreply,
       socket
       |> put_flash(:error, gettext("You do not have access to this workspace."))
       |> redirect(to: "/")}
    end
  end

  defp show_section(params, socket) do
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
       platform: load_platform(socket),
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
    open_admin(socket, kind, params["id"])
  end

  def handle_event("close", _, socket), do: {:noreply, assign(socket, modal: nil, error: nil)}

  def handle_event("invitation_copied", %{"ok" => ok}, socket) do
    text =
      if ok,
        do: gettext("Link copied"),
        else: gettext("Copy failed. Select and copy the link manually.")

    {:noreply, assign(socket, copy_status: text)}
  end

  def handle_event(
        "save_staff",
        %{"staff" => params},
        %{assigns: %{modal: {"staff", id}}} = socket
      ) do
    result =
      if socket.assigns.preview? do
        PreviewAdministration.change_staff(
          socket.assigns.state,
          socket.assigns.actor_id,
          id,
          params
        )
      else
        AdminWorkspace.reassign(socket.assigns.current_user, id, params)
      end

    complete(socket, result)
  end

  def handle_event(
        "save_role",
        %{"member" => %{"role" => role}},
        %{assigns: %{modal: {"member", id}}} = socket
      ) do
    complete(
      socket,
      if(socket.assigns.preview?,
        do:
          PreviewAdministration.change_role(
            socket.assigns.state,
            socket.assigns.actor_id,
            id,
            role
          ),
        else: Accounts.change_role(socket.assigns.current_user, id, role)
      )
    )
  end

  def handle_event("confirm_remove", _, %{assigns: %{modal: {"member", id}}} = socket) do
    {:noreply, assign(socket, modal: {"remove", id}, error: nil)}
  end

  def handle_event("remove_member", _, %{assigns: %{modal: {"remove", id}}} = socket) do
    complete(
      socket,
      if(socket.assigns.preview?,
        do:
          PreviewAdministration.remove_teacher(socket.assigns.state, socket.assigns.actor_id, id),
        else: Accounts.remove_teacher(socket.assigns.current_user, id)
      )
    )
  end

  def handle_event("save_institution", %{"institution" => %{"name" => name}}, socket) do
    result =
      if socket.assigns.preview?,
        do: PreviewAdministration.rename(socket.assigns.state, socket.assigns.actor_id, name),
        else: Accounts.rename_institution(socket.assigns.current_user, name)

    complete(socket, result)
  end

  def handle_event("save_footer", %{"footer" => params}, socket) when is_map(params) do
    result =
      if socket.assigns.preview? do
        socket.assigns.footer_links
        |> Accounts.change_footer_links(params)
        |> Ecto.Changeset.apply_action(:update)
        |> case do
          {:ok, institution} -> {:ok, Map.take(institution, Accounts.Institution.footer_fields())}
          error -> error
        end
      else
        Accounts.update_footer_links(socket.assigns.current_user, params)
      end

    case result do
      {:ok, links} ->
        socket
        |> assign(
          footer_links: links,
          footer_form: to_form(Accounts.change_footer_links(links), as: :footer)
        )
        |> complete({:ok, socket.assigns.state})

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(footer_form: to_form(changeset, as: :footer), notice: nil)
         |> push_event("focus-invalid", %{id: "footer-form"})}

      error ->
        complete(socket, error)
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp complete(socket, {:ok, result}) do
    state =
      if socket.assigns.preview?,
        do: result,
        else: initial_state(false, socket.assigns.current_user)

    {:noreply,
     assign(socket,
       state: state,
       modal: nil,
       error: nil,
       notice:
         if(socket.assigns.preview?,
           do: gettext("Changes saved in this preview."),
           else: gettext("Changes saved.")
         )
     )}
  end

  defp complete(socket, :ok), do: complete(socket, {:ok, nil})

  defp complete(socket, {:error, reason}) do
    message =
      if socket.assigns.preview? and is_binary(reason),
        do: reason,
        else: AdminWorkspace.error(reason)

    {:noreply, assign(socket, error: message)}
  end

  defp initial_state(true, _actor), do: PreviewAdministration.initial()

  defp initial_state(false, actor) do
    case AdminWorkspace.load(actor) do
      {:ok, state} ->
        state

      {:error, _} ->
        %{
          name: Accounts.institution().name,
          teachers: [],
          classrooms: [],
          students: 0,
          history: []
        }
    end
  end

  defp allowed?(%{assigns: %{preview?: true}}), do: true

  defp allowed?(%{assigns: %{live_action: :platform, current_user: actor}}),
    do: Accounts.operator?(actor)

  defp allowed?(%{assigns: %{current_user: actor}}), do: Accounts.admin?(actor)

  defp load_platform(%{assigns: %{preview?: true, platform: platform}}), do: platform

  defp load_platform(%{assigns: %{live_action: :platform, current_user: actor}}),
    do: GradePushWeb.PlatformWorkspace.load(actor)

  defp load_platform(_), do: nil

  defp open_admin(socket, "invite", _id) do
    result =
      if socket.assigns.preview?,
        do: {:ok, %{token: "institution-demo"}},
        else: Accounts.create_teacher_invitation(socket.assigns.current_user)

    case result do
      {:ok, %{token: token}} ->
        origin =
          if socket.assigns.preview?,
            do: "https://gradepush.example",
            else: GradePushWeb.Endpoint.url()

        url = origin <> "/join/teacher/" <> token

        {:noreply,
         assign(socket, modal: {"invite", nil}, invitation_url: url, error: nil, copy_status: nil)}

      {:error, _} = error ->
        complete(socket, error)
    end
  end

  defp open_admin(socket, kind, id) do
    record =
      if kind == "staff",
        do: AdminWorkspace.classroom(socket.assigns.state, id),
        else: AdminWorkspace.teacher(socket.assigns.state, id)

    if record,
      do: {:noreply, assign(socket, modal: {kind, id}, error: nil)},
      else: complete(socket, {:error, :not_found})
  end

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
