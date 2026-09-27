defmodule GradePushWeb.InvitationLive do
  @moduledoc false
  use GradePushWeb, :live_view

  alias GradePush.{Accounts, Assignments, Classrooms}
  alias GradePushWeb.{AdminWorkspace, Markdown, WorkspaceLayout}

  @impl true
  def mount(_params, _session, %{assigns: %{current_user: nil}} = socket),
    do: {:ok, redirect(socket, to: "/auth/sign-in")}

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
       profile:
         to_form(
           %{
             "name" =>
               socket.assigns.current_user.student_name || socket.assigns.current_user.name,
             "student_id" => socket.assigns.current_user.student_id
           },
           as: :profile
         )
     )}
  end

  @impl true
  def handle_params(%{"kind" => kind, "token" => token}, uri, socket) do
    result =
      case kind do
        "teacher" -> Accounts.lookup_teacher_invitation(token)
        "classroom" -> Classrooms.classroom_invitation(token)
        "assignment" -> Assignments.assignment_invitation(token)
        _ -> {:error, :invalid_invitation}
      end

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
       path: URI.parse(uri).path,
       error: nil
     )}
  end

  @impl true
  def handle_event("accept", params, socket) do
    attrs = Map.get(params, "profile", %{})
    actor = socket.assigns.current_user
    token = socket.assigns.token

    result =
      case socket.assigns.kind do
        "teacher" -> Accounts.accept_teacher_invitation(actor, token)
        "classroom" -> Classrooms.accept_class_invitation(actor, token, attrs)
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

  defp error(reason) when reason in [:teacher_assigned_teams, :team_assignment_required],
    do: gettext("Your teacher needs to assign you to a team before you can accept.")

  defp error(reason), do: AdminWorkspace.error(reason)

  defp title(%{assignment: assignment}), do: assignment.title
  defp title(%{classroom: classroom}), do: classroom.title
  defp title(%{institution_name: name}), do: name

  defp team_assignment?(%{assignment: %{kind: "team", team_mode: "students"}}), do: true
  defp team_assignment?(_), do: false
end
