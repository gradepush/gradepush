defmodule GradePushWeb.AdminWorkspace do
  @moduledoc false
  use Gettext, backend: GradePushWeb.Gettext

  alias GradePush.{Accounts, Classrooms}
  alias GradePushWeb.Presentation

  def load(actor) do
    with {:ok, teachers} <- Accounts.list_teachers(actor),
         {:ok, classes} <- Classrooms.list_admin_classrooms(actor),
         {:ok, stats} <- Accounts.institution_stats(actor),
         {:ok, events} <- Accounts.list_audit(actor, :institution) do
      {:ok,
       %{
         name: Accounts.institution().name,
         teachers: Enum.map(teachers, &teacher_record/1),
         classrooms: Enum.map(classes, &classroom_record/1),
         students: stats.students,
         history: Enum.map(events, &event/1)
       }}
    end
  end

  def teacher(state, id), do: Enum.find(state.teachers, &(&1.id == id))
  def classroom(state, id), do: Enum.find(state.classrooms, &(&1.id == id))
  def class_count(state, id), do: Enum.count(state.classrooms, &(id in &1.teachers))

  def candidates(state, classroom, actor_id) do
    Enum.reject(state.teachers, &(&1.id == actor_id or &1.id in classroom.teachers))
  end

  def reassign(actor, classroom_id, params) do
    with {:ok, classroom_id} <- Ecto.Type.cast(:id, classroom_id),
         {:ok, teacher_id} <- Ecto.Type.cast(:id, params["teacher"]),
         {:ok, replaced_id} <- optional_id(params["replace"]) do
      Classrooms.reassign_teacher(actor, classroom_id, teacher_id, replaced_id)
    else
      _ -> {:error, :invalid_teacher}
    end
  end

  defp optional_id(value) when value in [nil, ""], do: {:ok, nil}
  defp optional_id(value), do: Ecto.Type.cast(:id, value)

  def error(:demo_invitations_disabled), do: gettext("Invitations are disabled in demo mode.")
  def error(:unauthorized), do: gettext("You no longer have permission to do this.")
  def error(:not_found), do: gettext("This record is no longer available.")
  def error(:last_admin), do: gettext("Keep at least one institution administrator.")
  def error(:last_administrator), do: gettext("Keep at least one institution administrator.")
  def error(:cannot_remove_self), do: gettext("You cannot remove your own account.")
  def error(:invalid_student_profile), do: gettext("Enter your name and student ID.")

  def error(:self_assignment),
    do: gettext("You cannot assign yourself. A classroom teacher can invite you.")

  def error(:classrooms_assigned),
    do: gettext("Reassign this teacher’s classrooms before removing them.")

  def error(%Ecto.Changeset{}), do: gettext("Check the entered information and try again.")
  def error(_), do: gettext("This change could not be saved. Refresh the page and try again.")

  def event(event) do
    %{
      actor: event.actor_name,
      action: action(event.action),
      target: event.target,
      time: Presentation.datetime(event.inserted_at)
    }
  end

  defp teacher_record(%{user: user, role: role}) do
    user |> Presentation.user() |> Map.merge(%{id: to_string(user.id), admin?: role == :admin})
  end

  defp classroom_record(%{classroom: classroom} = metadata) do
    %{
      id: to_string(classroom.id),
      title: Presentation.text(classroom.title),
      code: classroom.code || "",
      students: metadata.students_count,
      teachers: Enum.map(metadata.teachers, &to_string(&1.id))
    }
  end

  defp action("institution.renamed"), do: gettext("Institution renamed")
  defp action("institution.footer_updated"), do: gettext("Institution links updated")
  defp action("teacher.invited"), do: gettext("Teacher invited")
  defp action("teacher.removed"), do: gettext("Teacher removed from institution")
  defp action("teacher.role_changed"), do: gettext("Institution role changed")
  defp action("classroom.teacher_added"), do: gettext("Teacher added to classroom")
  defp action("classroom.teacher_replaced"), do: gettext("Classroom teacher replaced")
  defp action("installation.completed"), do: gettext("Instance initialized")
  defp action("installation.initialized"), do: gettext("Instance initialized")
  defp action("classroom.teacher_reassigned"), do: gettext("Classroom teachers changed")
  defp action("teacher.invitation.accepted"), do: gettext("Teacher joined the institution")
  defp action(value), do: value
end
