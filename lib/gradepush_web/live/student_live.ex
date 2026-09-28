defmodule GradePushWeb.StudentLive do
  @moduledoc false
  use GradePushWeb, :live_view

  alias GradePush.{Accounts, Assignments, Classrooms, Submissions}

  alias GradePushWeb.{
    ClassroomComponents,
    GradingComponents,
    Markdown,
    Presentation,
    StudentScheduleComponents,
    WorkspaceLayout
  }

  @impl true
  def mount(_params, _session, %{assigns: %{current_user: nil}} = socket),
    do: {:ok, redirect(socket, to: "/auth/sign-in")}

  def mount(_params, session, socket) do
    locale = if session["locale"] in ~w(en fr), do: session["locale"], else: "en"
    Gettext.put_locale(GradePushWeb.Gettext, locale)

    {:ok,
     assign(socket,
       page_title: gettext("My classrooms"),
       locale: locale,
       user: Presentation.user(socket.assigns.current_user),
       institution: Accounts.institution().name,
       contexts: Presentation.contexts(socket.assigns.current_user),
       classes: [],
       classroom: nil,
       assignments: [],
       schedule: nil,
       assignment: nil,
       subject: nil,
       repository: nil,
       latest_push: nil,
       subscribed_topics: [],
       route_params: %{},
       path: "/student/classrooms",
       error: nil
     )}
  end

  @impl true
  def handle_params(params, uri, socket) do
    actor = socket.assigns.current_user
    socket = assign(socket, path: URI.parse(uri).path, route_params: params, error: nil)

    case socket.assigns.live_action do
      :index ->
        classes =
          case Classrooms.list_student_classrooms(actor) do
            {:ok, classes} -> classes
            {:error, _} -> []
          end

        {:noreply,
         socket
         |> assign(classes: classes, page_title: gettext("My classrooms"))
         |> subscribe_to(["user:#{actor.id}" | Enum.map(classes, &"classroom:#{&1.id}")])}

      :schedule ->
        load_schedule(socket, params)

      action when action in [:show, :assignment] ->
        load_classroom(socket, params)
    end
  end

  @impl true
  def handle_info({event, _id}, %{assigns: %{live_action: :schedule}} = socket)
      when event in [:repository_changed, :push_recorded, :grade_recorded, :grade_untrusted],
      do: {:noreply, socket}

  def handle_info(
        {:student_removed, user_id},
        %{assigns: %{current_user: %{id: user_id}}} = socket
      ),
      do: refresh(socket)

  def handle_info({event, _id}, socket)
      when event in [
             :classroom_joined,
             :classroom_updated,
             :classroom_removed,
             :classroom_archived,
             :assignment_created,
             :assignment_updated,
             :assignment_archived,
             :assignment_accepted,
             :team_changed,
             :repository_changed,
             :push_recorded,
             :grade_recorded,
             :grade_untrusted,
             :extension_changed
           ],
      do: refresh(socket)

  def handle_info(_message, socket), do: {:noreply, socket}

  defp refresh(socket) do
    if socket.assigns.live_action in [:index, :schedule] do
      handle_params(socket.assigns.route_params, socket.assigns.path, socket)
    else
      load_classroom(socket, socket.assigns.route_params)
    end
  end

  defp load_schedule(socket, params) do
    actor = socket.assigns.current_user

    classes =
      case Classrooms.list_student_classrooms(actor) do
        {:ok, classes} -> classes
        {:error, _} -> []
      end

    entries =
      case Assignments.list_student_schedule(actor) do
        {:ok, entries} -> entries
        {:error, _} -> []
      end

    {:noreply,
     socket
     |> assign(
       schedule: StudentScheduleComponents.prepare(entries, params),
       page_title: gettext("My assignments")
     )
     |> subscribe_to(
       ["user:#{actor.id}"] ++
         Enum.map(classes, &"classroom:#{&1.id}") ++
         Enum.map(entries, &"assignment:#{&1.assignment.id}")
     )}
  end

  defp load_classroom(socket, params) do
    actor = socket.assigns.current_user

    with {:ok, classroom} <- Classrooms.get_student_classroom(actor, params["slug"]),
         {:ok, assignments} <- Assignments.list_student_assignments(actor, classroom.id) do
      result =
        if is_binary(params["assignment"]),
          do: Assignments.get_student_assignment(actor, classroom.id, params["assignment"]),
          else: {:error, :not_found}

      details =
        case result do
          {:ok, details} -> details
          _ -> %{assignment: nil, subject: nil, repository: nil, latest_push: nil}
        end

      assignment = details.assignment

      {:noreply,
       socket
       |> assign(
         classroom: classroom,
         assignments: assignments,
         assignment: assignment,
         subject: details.subject,
         repository: details.repository,
         latest_push: details.latest_push,
         page_title: if(assignment, do: assignment.title, else: classroom.title)
       )
       |> subscribe_to(
         ["user:#{actor.id}", "classroom:#{classroom.id}"] ++
           submission_topics(if(assignment, do: [details], else: assignments))
       )}
    else
      _ ->
        {:noreply,
         socket
         |> assign(
           classroom: nil,
           assignment: nil,
           assignments: [],
           subject: nil,
           repository: nil,
           latest_push: nil,
           page_title: gettext("This page is not available.")
         )
         |> subscribe_to([])}
    end
  end

  defp subscribe_to(socket, topics) do
    if connected?(socket) do
      previous = socket.assigns.subscribed_topics
      Enum.each(previous -- topics, &Phoenix.PubSub.unsubscribe(GradePush.PubSub, &1))
      Enum.each(topics -- previous, &Phoenix.PubSub.subscribe(GradePush.PubSub, &1))
    end

    assign(socket, subscribed_topics: topics)
  end

  defp submission_topics(entries) do
    Enum.flat_map(entries, fn
      %{subject: %{id: id}} -> ["submission:#{id}"]
      _ -> []
    end)
  end

  defp repository_url(repository) do
    case repository do
      %{html_url: "https://github.com/" <> _ = url} -> url
      _ -> nil
    end
  end

  defp language_url(path, params, locale) do
    query =
      params
      |> Map.take(~w(view month))
      |> Enum.filter(fn {_key, value} -> is_binary(value) end)
      |> Map.new()
      |> Map.put("locale", locale)

    path <> "?" <> URI.encode_query(query)
  end

  defp due(nil), do: gettext("No deadline")
  defp due(datetime), do: Presentation.datetime(datetime)

  defp deadline_label(nil), do: gettext("No deadline")
  defp deadline_label(datetime), do: gettext("Due %{date}", date: due(datetime))

  defp push_time(nil), do: "—"
  defp push_time(push), do: Presentation.datetime(push.observed_at)

  defp team_members(team) do
    team.members
    |> Enum.filter(&is_nil(&1.left_at))
    |> Enum.map_join(", ", &Presentation.user(&1.user).name)
  end

  defp deadline(assignment, %{extension_until: extension}),
    do: Submissions.effective_deadline(assignment.deadline_at, extension)

  defp deadline(assignment, _subject), do: assignment.deadline_at

  defp repository_failed?(%{state: "failed"}), do: true
  defp repository_failed?(_), do: false

  defp assignment_path(classroom, assignment),
    do: "/student/classrooms/#{classroom.slug}/assignments/#{assignment.slug}"
end
