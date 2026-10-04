defmodule GradePushWeb.InvitationLive do
  @moduledoc false
  use GradePushWeb, :live_view

  alias GradePush.{Accounts, Assignments, Classrooms}
  alias GradePushWeb.{AdminWorkspace, Presentation}
  alias GradePushWeb.Preview.Invitations

  @impl true
  def mount(_params, session, socket) do
    locale = if session["locale"] in ~w(en fr), do: session["locale"], else: "en"
    Gettext.put_locale(GradePushWeb.Gettext, locale)

    {:ok,
     assign(socket,
       locale: locale,
       page_title: gettext("Invitation"),
       invitation: nil,
       token: nil,
       kind: nil,
       path: "/",
       error: nil,
       participant: socket.assigns.current_user,
       profile: to_form(%{"team_id" => "", "team_name" => ""}, as: :profile)
     )}
  end

  @impl true
  def handle_params(%{"kind" => kind, "token" => token} = params, uri, socket) do
    preview =
      if socket.assigns.preview?,
        do: Invitations.lookup(kind, token, params)

    result = lookup(preview, kind, token, socket.assigns.current_user)

    invitation =
      case result do
        {:ok, invitation} -> invitation
        _ -> nil
      end

    {:noreply,
     assign(socket,
       kind: kind,
       token: token,
       invitation: invitation,
       participant: if(preview, do: preview.participant, else: socket.assigns.current_user),
       design_preview: not is_nil(preview),
       path: URI.parse(uri).path,
       error: nil
     )}
  end

  defp lookup(%{invitation: invitation}, _kind, _token, _actor), do: {:ok, invitation}
  defp lookup(_, "teacher", token, _actor), do: Accounts.lookup_teacher_invitation(token)
  defp lookup(_, "classroom", token, _actor), do: Classrooms.classroom_invitation(token)
  defp lookup(_, "assignment", token, actor), do: Assignments.assignment_invitation(token, actor)
  defp lookup(_, _kind, _token, _actor), do: {:error, :invalid_invitation}

  @impl true
  def handle_event("change-team", %{"profile" => attrs}, socket) do
    {:noreply, assign(socket, profile: to_form(attrs, as: :profile), error: nil)}
  end

  def handle_event("accept", params, %{assigns: %{design_preview: true}} = socket) do
    case Invitations.accept(socket.assigns.invitation, Map.get(params, "profile", %{})) do
      {:ok, query} ->
        {:noreply,
         redirect(socket,
           to:
             destination(socket.assigns) <>
               "?" <> URI.encode_query(Map.put(query, :locale, socket.assigns.locale))
         )}

      {:error, reason} ->
        {:noreply, assign(socket, error: error(reason))}
    end
  end

  def handle_event("accept", _params, %{assigns: %{current_user: nil}} = socket) do
    {:noreply, redirect(socket, to: "/auth/sign-in")}
  end

  def handle_event("accept", params, socket) do
    attrs = Map.take(Map.get(params, "profile", %{}), ["team_id", "team_name"])
    actor = socket.assigns.current_user
    token = socket.assigns.token

    result =
      case socket.assigns.kind do
        "teacher" -> Accounts.accept_teacher_invitation(actor, token)
        "classroom" -> Classrooms.accept_class_invitation(actor, token, %{})
        "assignment" -> Assignments.accept_assignment_invitation(actor, token, attrs)
        _ -> {:error, :invalid_invitation}
      end

    case result do
      {:ok, _} ->
        {:noreply, redirect(socket, to: destination(socket.assigns))}

      {:error, reason} ->
        {:noreply, assign(socket, error: error(reason), profile: to_form(attrs, as: :profile))}
    end
  end

  defp destination(%{kind: "teacher"}), do: "/classrooms"

  defp destination(%{kind: "classroom", invitation: %{classroom: classroom}}),
    do: "/student/classrooms/#{classroom.slug}"

  defp destination(%{
         kind: "assignment",
         invitation: %{assignment: assignment, classroom: classroom}
       }),
       do: "/student/classrooms/#{classroom.slug}/assignments/#{assignment.slug}"

  defp destination(_), do: "/student/classrooms"

  defp error(:invalid_invitation),
    do:
      gettext(
        "This invitation has expired or is no longer available. Ask your teacher for a new link."
      )

  defp error(:team_full), do: gettext("This team is full. Choose another team.")
  defp error(:team_required), do: gettext("Choose a team or enter a new team name.")
  defp error(:invalid_team), do: gettext("This team is no longer available. Choose another team.")

  defp error(:already_in_team),
    do: gettext("You already belong to a team for this assignment. Reload this page to continue.")

  defp error(reason) when reason in [:teacher_assigned_teams, :team_assignment_required],
    do: gettext("Your teacher needs to assign you to a team before you can accept.")

  defp error(reason), do: AdminWorkspace.error(reason)

  defp title(%{assignment: assignment}), do: assignment.title
  defp title(%{classroom: classroom}), do: classroom.title
  defp title(%{institution_name: name}), do: name

  defp student_teams?(%{assignment: %{kind: "team", team_mode: "students"}, current_team: nil}),
    do: true

  defp student_teams?(_), do: false

  defp waiting_for_team?(%{assignment: %{kind: "team", team_mode: "teacher"}, current_team: nil}),
    do: true

  defp waiting_for_team?(_), do: false
end
