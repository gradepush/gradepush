defmodule GradePushWeb.TeacherLive do
  @moduledoc false
  use GradePushWeb, :live_view

  alias GradePush.{Accounts, Classrooms, Installation, Submissions}
  alias GradePush.Assignments, as: AssignmentsContext
  alias GradePushWeb.AccountComponents
  alias GradePushWeb.AssignmentComponents
  alias GradePushWeb.AssignmentEditor
  alias GradePushWeb.ClassroomComponents
  alias GradePushWeb.Forms.AssignmentDraft
  alias GradePushWeb.GradingComponents
  alias GradePushWeb.Presentation
  alias GradePushWeb.Preview.AssignmentEditing
  alias GradePushWeb.Preview.Assignments, as: PreviewAssignments
  alias GradePushWeb.Preview.Fixtures
  alias GradePushWeb.TeacherWorkspace
  alias GradePushWeb.WorkspaceLayout

  @impl true
  def mount(_params, session, socket) do
    locale = if session["locale"] in ~w(en fr), do: session["locale"], else: "en"
    Gettext.put_locale(GradePushWeb.Gettext, locale)
    preview? = Map.get(socket.assigns, :preview?, false)
    current_user = Map.get(socket.assigns, :current_user)

    classes = if preview?, do: preview_classes(), else: []

    organizations = if preview?, do: Fixtures.organizations(), else: []

    user = if preview?, do: hd(Fixtures.teachers()), else: Presentation.user(current_user)
    institution = if preview?, do: Fixtures.institution(), else: institution_name()

    {:ok,
     assign(socket,
       page_title: gettext("My classrooms"),
       locale: locale,
       preview?: preview?,
       current_user: current_user,
       user: user,
       institution: institution,
       organizations: organizations,
       github_app: if(preview?, do: nil, else: Installation.github_app_metadata()),
       class_form_errors: [],
       available_organizations: [],
       available_classroom_teachers: [],
       classes: classes,
       assignments:
         if(preview?,
           do: Enum.flat_map(classes, &PreviewAssignments.for_classroom(&1.slug)),
           else: []
         ),
       assignment_form: nil,
       assignment_params: %{},
       extension_params: %{},
       instructions_preview: false,
       classroom: nil,
       classroom_record: nil,
       members: [],
       assignment: nil,
       assignment_record: nil,
       assignment_details: nil,
       assignment_subjects: [],
       teams: [],
       active_team_id: nil,
       team_action: nil,
       assignment_activity: %{},
       subscribed_topics: [],
       refresh_pending?: false,
       templates: [],
       templates_status: :idle,
       invitation_url: nil,
       submission_filter: "all",
       assignment_tab: "submissions",
       settings_section: "account",
       tab: "assignments",
       query: "",
       modal: nil,
       pending_teacher: nil,
       error: nil,
       notice: nil,
       path: "/",
       scenario: nil,
       route_params: %{}
     )}
  end

  @impl true
  def handle_params(params, uri, socket) do
    if socket.assigns.preview?,
      do: handle_preview_params(params, uri, socket),
      else: handle_real_params(params, uri, socket)
  end

  defp handle_preview_params(params, uri, socket) do
    classroom = Enum.find(socket.assigns.classes, &(&1.slug == params["slug"]))

    assignment =
      Enum.find(
        socket.assigns.assignments,
        &(&1.classroom == params["slug"] and &1.key == params["assignment"])
      )

    editor_state = preview_editor_state(classroom, assignment, socket.assigns.locale)

    {:noreply,
     assign(socket,
       classroom: classroom,
       classroom_record: nil,
       members: if(classroom, do: classroom.members, else: []),
       assignment: assignment,
       assignment_record: nil,
       assignment_details: editor_state.details,
       assignment_subjects: [],
       teams: [],
       assignment_activity: %{},
       extension_params: %{},
       assignment_form: editor_state.form,
       templates: editor_state.templates,
       assignment_params: editor_state.params,
       instructions_preview: false,
       assignment_tab: assignment_tab(params),
       settings_section: settings_section(params),
       page_title:
         editor_title(socket.assigns.live_action, classroom, assignment, socket.assigns.locale),
       submission_filter: "all",
       tab: classroom_tab(params),
       path: URI.parse(uri).path,
       invitation_url: nil,
       available_organizations: [],
       available_classroom_teachers: [],
       route_params: params,
       scenario: params["scenario"],
       query: "",
       modal: nil,
       pending_teacher: nil,
       notice: nil,
       error: nil
     )}
  end

  defp preview_editor_state(classroom, assignment, locale) do
    params = AssignmentEditing.params(assignment, locale)

    %{
      params: params,
      form: preview_editor_form(classroom, params, assignment, locale),
      details: preview_assignment_details(classroom, assignment, locale),
      templates: preview_templates(classroom)
    }
  end

  defp preview_editor_form(nil, _params, _assignment, _locale), do: nil

  defp preview_editor_form(classroom, params, assignment, locale) do
    to_form(AssignmentEditing.changeset(params, assignment, classroom, locale), as: :assignment)
  end

  defp preview_assignment_details(nil, _assignment, _locale), do: nil
  defp preview_assignment_details(_classroom, nil, _locale), do: nil

  defp preview_assignment_details(classroom, assignment, locale),
    do: PreviewAssignments.details(assignment, classroom, "", "all", locale)

  defp preview_templates(nil), do: []
  defp preview_templates(classroom), do: AssignmentEditing.templates(classroom)

  defp handle_real_params(params, uri, socket) do
    actor = socket.assigns.current_user
    locale = socket.assigns.locale
    classroom_state = real_classroom_state(actor, params["slug"])

    assignment_state =
      real_assignment_state(actor, classroom_state, socket, params["assignment"], locale)

    active_team_id =
      case Enum.find(assignment_state.teams, &(&1.id == socket.assigns.active_team_id)) ||
             List.first(assignment_state.teams) do
        nil -> nil
        team -> team.id
      end

    classroom_record = classroom_state.classroom_record
    assignment_record = assignment_state.assignment_record
    socket = subscribe_to_workspace(socket, classroom_record, assignment_record)

    assigns =
      Map.merge(classroom_state, assignment_state)
      |> Map.merge(%{
        assignments:
          Enum.map(
            classroom_state.assignment_records,
            &TeacherWorkspace.assignment(&1, classroom_state.classroom)
          ),
        instructions_preview: false,
        assignment_tab: assignment_tab(params),
        settings_section: settings_section(params),
        invitation_url: nil,
        available_organizations: [],
        page_title:
          editor_title(
            socket.assigns.live_action,
            classroom_state.classroom,
            assignment_state.assignment,
            locale
          ),
        submission_filter: "all",
        tab: classroom_tab(params),
        path: URI.parse(uri).path,
        scenario: nil,
        route_params: params,
        query: "",
        active_team_id: active_team_id,
        modal: nil,
        pending_teacher: nil,
        notice: Phoenix.Flash.get(socket.assigns.flash, :info),
        error: Phoenix.Flash.get(socket.assigns.flash, :error)
      })

    socket = socket |> cancel_async(:assignment_templates) |> assign(assigns) |> load_templates()

    if socket.assigns.live_action == :settings and params["connect"] == "true" do
      socket
      |> assign(modal: {"connect_organization", nil})
      |> load_available_organizations()
    else
      {:noreply, socket}
    end
  end

  defp real_classroom_state(actor, slug) do
    workspace =
      unwrap(Classrooms.teacher_workspace(actor, slug), %{
        classes: [],
        classroom: nil,
        students: [],
        connections: []
      })

    classroom_record = workspace.classroom
    enrollments = workspace.students

    classroom = if classroom_record, do: TeacherWorkspace.classroom(classroom_record, enrollments)
    members = if classroom, do: classroom.members, else: []

    assignment_records =
      if classroom_record,
        do: unwrap(AssignmentsContext.list_assignments(actor, classroom_record.id), []),
        else: []

    %{
      classroom_record: classroom_record,
      classroom: classroom,
      members: members,
      assignment_records: assignment_records,
      classes: Enum.map(workspace.classes, &TeacherWorkspace.classroom/1),
      organizations: Enum.map(workspace.connections, &Map.from_struct/1)
    }
  end

  defp real_assignment_state(actor, classroom_state, socket, assignment_slug, locale) do
    assignment_record =
      Enum.find(classroom_state.assignment_records, &(&1.slug == assignment_slug))

    assignment =
      if assignment_record,
        do: TeacherWorkspace.assignment(assignment_record, classroom_state.classroom)

    editor_state =
      assignment_editor_state(
        classroom_state.classroom_record,
        assignment_record,
        socket.assigns.live_action
      )

    submission_state =
      submission_state(
        actor,
        assignment_record,
        assignment,
        classroom_state.classroom,
        socket.assigns.query,
        socket.assigns.submission_filter,
        locale
      )

    Map.merge(
      %{assignment_record: assignment_record, assignment: assignment},
      Map.merge(editor_state, submission_state)
    )
  end

  defp assignment_editor_state(classroom_record, assignment_record, action) do
    editor? = action in [:new_assignment, :edit_assignment] and not is_nil(classroom_record)

    templates =
      if (editor? and assignment_record) && assignment_record.template_repository,
        do: [assignment_record.template_repository],
        else: []

    params = TeacherWorkspace.assignment_params(assignment_record)

    form =
      if editor? do
        templates = include_locked_template(templates, assignment_record)

        params
        |> assignment_changeset(templates)
        |> to_form(as: :assignment)
      end

    %{templates: templates, assignment_params: params, assignment_form: form}
  end

  defp load_templates(socket) do
    if socket.assigns.assignment_form &&
         socket.assigns.live_action in [:new_assignment, :edit_assignment] &&
         (is_nil(socket.assigns.assignment_record) or
            socket.assigns.assignment_record.submissions_count == 0) do
      actor = socket.assigns.current_user
      classroom_id = socket.assigns.classroom_record.id

      socket
      |> assign(templates_status: :loading)
      |> start_async(:assignment_templates, fn ->
        Classrooms.list_templates(actor, classroom_id)
      end)
    else
      assign(socket, templates_status: :idle)
    end
  end

  @impl true
  def handle_async(:assignment_templates, {:exit, {:shutdown, :cancel}}, socket),
    do: {:noreply, socket}

  def handle_async(:assignment_templates, {:ok, {:ok, templates}}, socket) do
    templates = Enum.map(templates, &template_name/1)

    socket =
      socket
      |> assign(templates: templates, templates_status: :ready)
      |> assign_real_assignment_form(
        socket.assigns.assignment_params,
        socket.assigns.assignment_form.source.action
      )

    {:noreply, socket}
  end

  def handle_async(:assignment_templates, _failure, socket),
    do: {:noreply, assign(socket, templates_status: :error)}

  defp include_locked_template(templates, %{submissions_count: count, template_repository: repo})
       when count > 0 and is_binary(repo),
       do: Enum.uniq(templates ++ [repo])

  defp include_locked_template(templates, _assignment), do: templates

  defp submission_state(_actor, nil, _assignment, _classroom, _query, _filter, _locale),
    do: %{assignment_subjects: [], assignment_activity: %{}, teams: [], assignment_details: nil}

  defp submission_state(
         actor,
         assignment_record,
         assignment,
         classroom,
         query,
         filter,
         locale
       ) do
    subjects = unwrap(AssignmentsContext.list_submissions(actor, assignment_record.id), [])
    activities = unwrap(Submissions.list_assignment_activity(actor, assignment_record.id), %{})
    teams = teacher_teams(actor, assignment_record)

    details =
      TeacherWorkspace.details(
        assignment,
        classroom,
        teams,
        subjects,
        activities,
        query,
        filter,
        locale
      )

    %{
      assignment_subjects: subjects,
      assignment_activity: activities,
      teams: teams,
      assignment_details: details
    }
  end

  defp teacher_teams(actor, %{id: id, kind: "team", team_size: size}) do
    actor
    |> then(&AssignmentsContext.list_teams(&1, id))
    |> unwrap([])
    |> Enum.with_index(1)
    |> Enum.map(fn {team, number} -> TeacherWorkspace.team(team, number, size) end)
  end

  defp teacher_teams(_actor, _assignment), do: []

  defp assignment_tab(%{"view" => "tests"}), do: "tests"
  defp assignment_tab(_params), do: "submissions"

  defp settings_section(%{"section" => "organizations"}), do: "organizations"
  defp settings_section(_params), do: "account"

  defp classroom_tab(%{"tab" => "students"}), do: "students"
  defp classroom_tab(_params), do: "assignments"

  @impl true
  def handle_info(_message, %{assigns: %{preview?: true}} = socket), do: {:noreply, socket}

  def handle_info({_event, _id}, socket) do
    if refreshable_workspace?(socket.assigns) and not socket.assigns.refresh_pending? do
      Process.send_after(self(), :refresh_workspace, 50)
      {:noreply, assign(socket, refresh_pending?: true)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:refresh_workspace, socket) do
    socket = assign(socket, refresh_pending?: false)

    if refreshable_workspace?(socket.assigns),
      do: reload_real_workspace(socket, nil),
      else: {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_event("search", %{"query" => query}, socket),
    do: {:noreply, socket |> assign(query: query) |> refresh_assignment_details(query, "all")}

  def handle_event("filter_submissions", params, socket) do
    query = params["query"] || ""
    filter = params["status"] || "all"

    {:noreply,
     socket
     |> assign(query: query, submission_filter: filter)
     |> refresh_assignment_details(query, filter)}
  end

  def handle_event("retry_repository", %{"subject_id" => value}, socket) do
    with false <- socket.assigns.preview?,
         {:ok, subject_id} <- parse_id_result(value),
         %{id: ^subject_id, repository: %{state: "failed"}} <-
           Enum.find(socket.assigns.assignment_subjects, &(&1.id == subject_id)),
         %{id: _assignment_id} <- socket.assigns.assignment_record,
         {:ok, _repository} <-
           AssignmentsContext.retry_repository(socket.assigns.current_user, subject_id) do
      reload_real_workspace(socket, gettext("Repository setup has been queued again."))
    else
      {:error, :repository_ready} ->
        reload_real_workspace(socket, nil)

      {:error, :not_found} ->
        {:noreply, assign(socket, error: gettext("This submission is no longer available."))}

      {:error, _reason} ->
        {:noreply,
         assign(socket,
           error:
             gettext(
               "Could not retry repository setup. Check the GitHub connection and try again."
             )
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("create_team", %{"team" => %{"name" => name}}, socket) do
    cond do
      not teacher_team_assignment?(socket.assigns) ->
        {:noreply, socket}

      not is_binary(name) or String.trim(name) == "" ->
        {:noreply, assign(socket, error: gettext("Enter a team name."))}

      true ->
        case AssignmentsContext.create_team(
               socket.assigns.current_user,
               socket.assigns.assignment_record.id,
               %{name: String.trim(name)}
             ) do
          {:ok, team} ->
            socket
            |> assign(active_team_id: team.id, team_action: nil)
            |> reload_real_workspace(gettext("Team created."))

          {:error, reason} ->
            {:noreply, assign(socket, error: team_error(reason))}
        end
    end
  end

  def handle_event("select_team", %{"team_id" => value}, socket) do
    with true <- teacher_team_assignment?(socket.assigns),
         {:ok, team_id} <- parse_id_result(value),
         true <- Enum.any?(socket.assigns.teams, &(&1.id == team_id)) do
      {:noreply,
       assign(socket, active_team_id: team_id, team_action: nil, error: nil, notice: nil)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("team_action", %{"action" => action, "team_id" => value} = params, socket)
      when action in ["rename", "remove", "delete"] do
    with true <- teacher_team_assignment?(socket.assigns),
         {:ok, team_id} <- parse_id_result(value),
         team when not is_nil(team) <- Enum.find(socket.assigns.teams, &(&1.id == team_id)) do
      student = Enum.find(team.members, &(to_string(&1.id) == params["student_id"]))

      if action != "remove" or student do
        {:noreply,
         assign(socket,
           team_action: {action, team_id, student && student.id},
           error: nil,
           notice: nil
         )}
      else
        {:noreply, socket}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("cancel_team_action", _, socket),
    do: {:noreply, assign(socket, team_action: nil, error: nil)}

  def handle_event("rename_team", %{"team" => attrs}, socket) do
    with true <- teacher_team_assignment?(socket.assigns),
         {"rename", team_id, nil} <- socket.assigns.team_action,
         {:ok, _team} <-
           AssignmentsContext.rename_team(
             socket.assigns.current_user,
             socket.assigns.assignment_record.id,
             team_id,
             attrs
           ) do
      socket
      |> assign(team_action: nil)
      |> push_event("team-renamed", %{id: team_id})
      |> reload_real_workspace(gettext("Team renamed."))
    else
      {:error, reason} -> {:noreply, assign(socket, error: team_error(reason))}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("confirm_team_action", _, socket) do
    with true <- teacher_team_assignment?(socket.assigns),
         {action, team_id, student_id} when action in ["remove", "delete"] <-
           socket.assigns.team_action do
      result =
        if action == "remove" do
          AssignmentsContext.remove_team_member(
            socket.assigns.current_user,
            socket.assigns.assignment_record.id,
            team_id,
            student_id
          )
        else
          AssignmentsContext.delete_team(
            socket.assigns.current_user,
            socket.assigns.assignment_record.id,
            team_id
          )
        end

      case result do
        {:ok, _team} ->
          socket |> assign(team_action: nil) |> reload_real_workspace(team_action_notice(action))

        {:error, reason} ->
          {:noreply, assign(socket, error: team_error(reason))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("retry_repository_access", %{"subject_id" => value}, socket) do
    with false <- socket.assigns.preview?,
         {:ok, subject_id} <- parse_id_result(value),
         true <- Enum.any?(socket.assigns.assignment_subjects, &(&1.id == subject_id)),
         {:ok, _} <-
           AssignmentsContext.retry_repository_access(socket.assigns.current_user, subject_id) do
      reload_real_workspace(socket, gettext("GitHub access update queued."))
    else
      _ ->
        {:noreply, assign(socket, error: gettext("Could not update GitHub access. Try again."))}
    end
  end

  def handle_event(
        "add_team_member",
        %{"team_id" => team_value, "student_id" => student_value},
        socket
      ) do
    with true <- teacher_team_assignment?(socket.assigns),
         {:ok, team_id} <- parse_id_result(team_value),
         {:ok, student_id} <- parse_id_result(student_value),
         team when not is_nil(team) <- Enum.find(socket.assigns.teams, &(&1.id == team_id)),
         student when not is_nil(student) <-
           Enum.find(socket.assigns.members, &(&1.id == student_id)),
         true <- team.can_add? and not MapSet.member?(team.member_ids, student_id),
         {:ok, _updated_team} <-
           AssignmentsContext.add_team_member(
             socket.assigns.current_user,
             socket.assigns.assignment_record.id,
             team_id,
             student_id
           ) do
      reload_real_workspace(socket, gettext("Student added to the team."))
    else
      false -> {:noreply, assign(socket, error: gettext("Choose an available student and team."))}
      {:error, reason} -> {:noreply, assign(socket, error: team_error(reason))}
      _ -> {:noreply, assign(socket, error: gettext("Could not add this student to the team."))}
    end
  end

  def handle_event("validate_extension", %{"extension" => params}, socket) do
    if modal?(socket.assigns.modal, "deadline_extension"),
      do: {:noreply, assign(socket, extension_params: params)},
      else: {:noreply, socket}
  end

  def handle_event("save_extension", %{"extension" => params}, socket) do
    with {"deadline_extension", subject_value} <- socket.assigns.modal,
         {:ok, subject_id} <- parse_id_result(subject_value),
         %{id: assignment_id, deadline_at: deadline} <- socket.assigns.assignment_record,
         true <- not is_nil(deadline),
         %{id: ^subject_id} <-
           Enum.find(socket.assigns.assignment_subjects, &(&1.id == subject_id)),
         {:ok, extension_until} <- extension_deadline(params["deadline"]),
         {:ok, _subject} <-
           Submissions.set_extension(
             socket.assigns.current_user,
             assignment_id,
             subject_id,
             extension_until
           ) do
      {:noreply, socket} = reload_real_workspace(socket, gettext("Submission deadline updated."))
      {:noreply, assign(socket, modal: nil, extension_params: %{})}
    else
      {:error, :deadline_required} ->
        {:noreply,
         assign(socket,
           error: gettext("This assignment needs a deadline before it can be extended.")
         )}

      {:error, :extension_must_be_later} ->
        {:noreply,
         assign(socket, error: gettext("Choose a deadline later than the assignment deadline."))}

      {:error, :ambiguous_time} ->
        {:noreply,
         assign(socket,
           error: gettext("This local time occurs twice when clocks change. Choose another time.")
         )}

      {:error, :nonexistent_time} ->
        {:noreply,
         assign(socket,
           error:
             gettext("This local time does not exist when clocks change. Choose another time.")
         )}

      {:error, _reason} ->
        {:noreply,
         assign(socket, error: gettext("Could not update this submission deadline. Try again."))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("clear_extension", _, socket) do
    with {"deadline_extension", subject_value} <- socket.assigns.modal,
         {:ok, subject_id} <- parse_id_result(subject_value),
         %{id: assignment_id} <- socket.assigns.assignment_record,
         %{id: ^subject_id} <-
           Enum.find(socket.assigns.assignment_subjects, &(&1.id == subject_id)),
         {:ok, _subject} <-
           Submissions.set_extension(
             socket.assigns.current_user,
             assignment_id,
             subject_id,
             nil
           ) do
      {:noreply, socket} = reload_real_workspace(socket, gettext("Submission deadline reset."))
      {:noreply, assign(socket, modal: nil, extension_params: %{})}
    else
      _ ->
        {:noreply,
         assign(socket, error: gettext("Could not reset this submission deadline. Try again."))}
    end
  end

  def handle_event("open", %{"kind" => kind} = params, socket)
      when kind in ~w(create edit invite teachers remove assignment_invite clone_all connect_organization teams deadline_extension test_results) do
    if modal_resource_available?(kind, socket.assigns),
      do: open_modal(socket, kind, params),
      else: {:noreply, socket}
  end

  def handle_event("close", _, %{assigns: %{preview?: false, modal: {"teams", _}}} = socket) do
    socket
    |> assign(modal: nil, team_action: nil, error: nil)
    |> reload_real_workspace(socket.assigns.notice)
  end

  def handle_event("close", _, socket),
    do:
      {:noreply,
       assign(socket,
         modal: nil,
         team_action: nil,
         pending_teacher: nil,
         invitation_url: nil,
         available_organizations: [],
         available_classroom_teachers: [],
         extension_params: %{},
         error: nil
       )}

  def handle_event("validate_assignment", %{"assignment" => params}, socket) do
    if socket.assigns.assignment_form do
      form =
        if socket.assigns.preview?,
          do: assign_assignment_form(socket, params, :validate),
          else: assign_real_assignment_form(socket, params, :validate)

      {:noreply, form}
    else
      {:noreply, socket}
    end
  end

  def handle_event("retry_assignment_templates", _, socket) do
    if not socket.assigns.preview? and socket.assigns.templates_status == :error,
      do: {:noreply, load_templates(socket)},
      else: {:noreply, socket}
  end

  def handle_event("toggle_instructions_preview", _, socket) do
    {:noreply, update(socket, :instructions_preview, &(!&1))}
  end

  def handle_event("add_assignment_test", _, socket) do
    if socket.assigns.assignment_form do
      params = AssignmentEditing.add_test(socket.assigns.assignment_params)

      form =
        if socket.assigns.preview?,
          do: assign_assignment_form(socket, params),
          else: assign_real_assignment_form(socket, params, nil)

      {:noreply, form}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_assignment_test", %{"index" => index}, socket) do
    with true <- editable_assignment_tests?(socket.assigns),
         true <- is_binary(index),
         {index, ""} <- Integer.parse(index),
         true <- index >= 0,
         test when not is_nil(test) <- assignment_test_at(socket, index) do
      {:noreply,
       assign(socket, modal: {"remove_assignment_test", {index, test}}, error: nil, notice: nil)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("confirm_remove_assignment_test", _, socket) do
    with true <- editable_assignment_tests?(socket.assigns),
         {"remove_assignment_test", {index, test}} <- socket.assigns.modal,
         ^test <- assignment_test_at(socket, index) do
      params = AssignmentEditing.remove_test(socket.assigns.assignment_params, index)

      form =
        if socket.assigns.preview?,
          do: assign_assignment_form(socket, params),
          else: assign_real_assignment_form(socket, params, nil)

      {:noreply, form |> assign(modal: nil) |> push_event("assignment-test-removed", %{})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("save_assignment", %{"assignment" => params}, socket) do
    if socket.assigns.assignment_form == nil do
      {:noreply, socket}
    else
      socket =
        if socket.assigns.preview?,
          do: assign_assignment_form(socket, params, :insert),
          else: assign_real_assignment_form(socket, params, :insert)

      case Ecto.Changeset.apply_action(socket.assigns.assignment_form.source, :insert) do
        {:ok, draft} ->
          persist_assignment(socket, draft)

        {:error, _changeset} ->
          {:noreply, push_event(socket, "focus-invalid", %{id: "assignment-form"})}
      end
    end
  end

  def handle_event("save_class", %{"class" => params}, socket) do
    name = String.trim(params["name"] || "")
    code = String.trim(params["code"] || "")
    params = Map.put(params, "code", code)
    socket = assign(socket, class_form_params: params, class_form_errors: [])

    case {class_editor_open?(socket), name, code} do
      {false, _, _} ->
        {:noreply, socket}

      {true, "", _} ->
        {:noreply,
         socket
         |> assign(error: gettext("Enter a classroom name."), class_form_errors: [:name])
         |> push_event("focus-invalid", %{id: "class-form"})}

      {true, _, ""} ->
        {:noreply,
         socket
         |> assign(error: gettext("Enter a course code."), class_form_errors: [:code])
         |> push_event("focus-invalid", %{id: "class-form"})}

      {true, name, _} ->
        if params["semester"] in [nil, ""] == params["academic_year"] in [nil, ""],
          do: persist_class(socket, params, name),
          else:
            {:noreply,
             socket
             |> assign(
               error: gettext("Choose both a semester and a year, or leave both empty."),
               class_form_errors: [:semester, :academic_year]
             )
             |> push_event("focus-invalid", %{id: "class-form"})}
    end
  end

  def handle_event("remove_student", _, socket) do
    case modal?(socket.assigns.modal, "remove") do
      true -> remove_student_by_mode(socket)
      false -> {:noreply, socket}
    end
  end

  def handle_event("add_teacher", %{"teacher" => value}, socket) do
    case modal?(socket.assigns.modal, "teachers") do
      true -> add_teacher_by_mode(socket, value)
      false -> {:noreply, socket}
    end
  end

  def handle_event("connect_organization", params, socket) do
    if modal?(socket.assigns.modal, "connect_organization"),
      do: connect_real_organization(socket, params["organization"]),
      else: {:noreply, socket}
  end

  def handle_event("check_organization", %{"id" => value}, socket) do
    with {:ok, id} <- parse_id_result(value),
         true <- Enum.any?(socket.assigns.organizations, &(is_map(&1) and &1.id == id)) do
      feedback =
        case Classrooms.check_github_connection(socket.assigns.current_user, id) do
          :ok ->
            [notice: gettext("GitHub connection checked successfully."), error: nil]

          _ ->
            [
              notice: nil,
              error:
                gettext(
                  "Could not verify this connection. Check the GitHub App installation and permissions, then try again."
                )
            ]
        end

      {:noreply, assign(socket, feedback)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("request_teacher_removal", %{"teacher" => value}, socket) do
    teacher =
      if modal?(socket.assigns.modal, "teachers"),
        do:
          Enum.find(
            socket.assigns.classroom.teachers,
            &(to_string(teacher_option_value(&1)) == value and
                not_current_teacher?(&1, socket.assigns))
          )

    {:noreply, assign(socket, pending_teacher: teacher)}
  end

  def handle_event("cancel_teacher_removal", _, socket),
    do: {:noreply, assign(socket, pending_teacher: nil)}

  def handle_event("remove_teacher", _, socket) do
    case modal?(socket.assigns.modal, "teachers") do
      true -> remove_teacher_by_mode(socket)
      false -> {:noreply, socket}
    end
  end

  defp persist_assignment(socket, draft) do
    if socket.assigns.preview?,
      do: save_assignment(socket, draft),
      else: save_real_assignment(socket, draft)
  end

  defp class_editor_open?(socket),
    do: modal?(socket.assigns.modal, "create") or modal?(socket.assigns.modal, "edit")

  defp persist_class(socket, params, name) do
    if socket.assigns.preview?,
      do: save_class(socket, params, name),
      else: save_real_class(socket, params, name)
  end

  defp remove_student_by_mode(socket) do
    if socket.assigns.preview?,
      do: remove_preview_student(socket),
      else: remove_real_student(socket)
  end

  defp add_teacher_by_mode(socket, value) do
    if socket.assigns.preview?,
      do: add_preview_teacher(socket, value),
      else: add_real_teacher(socket, value)
  end

  defp remove_teacher_by_mode(socket) do
    if socket.assigns.preview?,
      do: remove_preview_teacher(socket),
      else: remove_real_teacher(socket)
  end

  defp remove_preview_student(socket) do
    case socket.assigns.modal do
      {"remove", handle} ->
        members = Enum.reject(socket.assigns.classroom.members, &(&1.handle == handle))

        {:noreply,
         socket
         |> update_class(%{members: members, students: length(members)})
         |> assign(modal: nil, notice: gettext("Student removed from this preview."))}

      _ ->
        {:noreply, socket}
    end
  end

  defp remove_preview_teacher(socket) do
    teacher = socket.assigns.pending_teacher

    if teacher && modal?(socket.assigns.modal, "teachers") &&
         length(socket.assigns.classroom.teachers) > 1 do
      teachers = Enum.reject(socket.assigns.classroom.teachers, &(&1.name == teacher.name))
      {:noreply, socket |> update_class(%{teachers: teachers}) |> assign(pending_teacher: nil)}
    else
      {:noreply, socket}
    end
  end

  defp open_modal(socket, kind, params) do
    handle = params["handle"]
    classroom_teachers = if kind == "teachers", do: available_teachers(socket.assigns), else: []

    subject =
      if kind in ~w(deadline_extension test_results) do
        with {:ok, subject_id} <- parse_id_result(params["subject_id"]),
             %{id: ^subject_id} = subject <-
               Enum.find(socket.assigns.assignment_subjects, &(&1.id == subject_id)) do
          subject
        else
          _ -> nil
        end
      end

    if kind in ~w(deadline_extension test_results) and is_nil(subject) do
      {:noreply, socket}
    else
      do_open_modal(socket, kind, handle, classroom_teachers, subject)
    end
  end

  defp do_open_modal(socket, kind, handle, classroom_teachers, subject) do
    modal_handle = if subject, do: subject.id, else: handle

    socket =
      assign(socket,
        modal: {kind, modal_handle},
        class_form_params: %{},
        class_form_errors: [],
        pending_teacher: nil,
        invitation_url: nil,
        available_organizations: [],
        available_classroom_teachers: classroom_teachers,
        extension_params:
          if(subject,
            do: %{"deadline" => GradePush.Time.format_local(subject.extension_until)},
            else: %{}
          ),
        error: nil,
        notice: nil
      )

    if preview_modal?(socket.assigns, kind) do
      {:noreply, socket}
    else
      case kind do
        "invite" ->
          create_invitation(
            socket,
            Classrooms,
            :create_class_invitation,
            socket.assigns.classroom_record
          )

        "assignment_invite" ->
          create_invitation(
            socket,
            AssignmentsContext,
            :create_assignment_invitation,
            socket.assigns.assignment_record
          )

        "connect_organization" ->
          load_available_organizations(socket)

        _ ->
          {:noreply, socket}
      end
    end
  end

  defp preview_modal?(assigns, kind),
    do: assigns.preview? or (kind == "assignment_invite" and GradePush.Demo.enabled?())

  defp create_invitation(socket, context, function, %{id: resource_id}) do
    case apply(context, function, [socket.assigns.current_user, resource_id]) do
      {:ok, %{token: token}} ->
        path =
          if function == :create_class_invitation,
            do: "/join/classroom/#{token}",
            else: "/join/assignment/#{token}"

        {:noreply, assign(socket, invitation_url: absolute_url(path))}

      {:error, :demo_invitations_disabled} ->
        {:noreply, assign(socket, error: gettext("Invitations are disabled in demo mode."))}

      {:error, _reason} ->
        {:noreply, assign(socket, error: gettext("Could not create this invitation. Try again."))}
    end
  end

  defp create_invitation(socket, _context, _function, _resource),
    do: {:noreply, assign(socket, error: gettext("Could not create this invitation. Try again."))}

  defp load_available_organizations(%{assigns: %{preview?: true}} = socket),
    do: {:noreply, socket}

  defp load_available_organizations(socket) do
    if GradePush.Demo.enabled?(),
      do: {:noreply, assign(socket, available_organizations: [], error: nil)},
      else: fetch_available_organizations(socket)
  end

  defp fetch_available_organizations(socket) do
    case Installation.list_user_organizations(socket.assigns.current_user) do
      {:ok, organizations} ->
        connected_ids = Enum.map(socket.assigns.organizations, & &1.installation_id)
        organizations = Enum.reject(organizations, &(&1.installation_id in connected_ids))
        {:noreply, assign(socket, available_organizations: organizations, error: nil)}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           available_organizations: [],
           error:
             if(reason == :github_reauthorization_required,
               do: AccountComponents.organization_error(reason),
               else: gettext("Could not load GitHub organizations. Try again.")
             )
         )}
    end
  end

  defp save_real_class(socket, params, name) do
    connection_id =
      if classroom_organization_locked?(socket.assigns),
        do: socket.assigns.classroom_record.github_connection_id,
        else: parse_id(params["github_connection_id"])

    attrs = %{
      title: name,
      code: params["code"],
      semester: params["semester"],
      academic_year: params["academic_year"],
      description: params["description"],
      github_connection_id: connection_id
    }

    result =
      case socket.assigns.modal do
        {"edit", _} ->
          Classrooms.update_classroom(
            socket.assigns.current_user,
            socket.assigns.classroom_record.id,
            attrs
          )

        _ ->
          Classrooms.create_classroom(socket.assigns.current_user, attrs)
      end

    case result do
      {:ok, classroom} ->
        {:noreply,
         socket
         |> assign(modal: nil, error: nil)
         |> push_patch(to: "/classrooms/#{classroom.slug}")}

      {:error, _reason} ->
        {:noreply,
         assign(socket, error: gettext("Could not save classroom. Check the form and try again."))}
    end
  end

  defp remove_real_student(socket) do
    with {"remove", handle} <- socket.assigns.modal,
         %{} = student <- Enum.find(socket.assigns.members, &(&1.handle == handle)),
         {:ok, _enrollment} <-
           Classrooms.remove_student(
             socket.assigns.current_user,
             socket.assigns.classroom_record.id,
             student.id
           ) do
      reload_real_workspace(socket, gettext("Student removed from this classroom."))
    else
      _reason ->
        {:noreply, assign(socket, error: gettext("Could not remove this student. Try again."))}
    end
  end

  defp add_preview_teacher(socket, name) do
    teacher = Enum.find(available_teachers(socket.assigns), &(&1.name == name))

    if teacher do
      {:noreply,
       update_class(socket, %{teachers: socket.assigns.classroom.teachers ++ [teacher]})}
    else
      {:noreply, socket}
    end
  end

  defp add_real_teacher(socket, value) do
    with {:ok, user_id} <- parse_id_result(value),
         {:ok, _teachers} <-
           Classrooms.add_teacher(
             socket.assigns.current_user,
             socket.assigns.classroom_record.id,
             user_id
           ) do
      reload_real_workspace(socket, gettext("Teacher added to this classroom."))
    else
      _reason ->
        {:noreply, assign(socket, error: gettext("Could not add this teacher. Try again."))}
    end
  end

  defp remove_real_teacher(socket) do
    teacher = socket.assigns.pending_teacher

    with %{id: user_id} <- teacher,
         {:ok, _teachers} <-
           Classrooms.remove_teacher(
             socket.assigns.current_user,
             socket.assigns.classroom_record.id,
             user_id
           ) do
      reload_real_workspace(socket, gettext("Teacher removed from this classroom."))
    else
      _reason ->
        {:noreply,
         assign(socket,
           error: gettext("Could not remove this teacher. At least one teacher must remain.")
         )}
    end
  end

  defp connect_real_organization(socket, installation_id) do
    with {:ok, id} <- parse_id_result(installation_id),
         false <- GradePush.Demo.enabled?(),
         {:ok, connection} <-
           Classrooms.connect_github_organization(socket.assigns.current_user, id) do
      reload_real_workspace(
        socket,
        gettext("%{organization} is connected to your account.", organization: connection.login)
      )
    else
      {:error, reason} ->
        {:noreply,
         assign(socket, error: GradePushWeb.AccountComponents.organization_error(reason))}

      _ ->
        {:noreply, socket}
    end
  end

  defp save_real_assignment(socket, draft) do
    case local_deadline(draft.deadline) do
      {:ok, deadline_at} ->
        attrs = %{
          title: draft.title,
          instructions: draft.instructions || "",
          kind: draft.kind,
          team_mode: draft.team_mode,
          team_size: draft.team_size,
          deadline_at: deadline_at,
          cutoff_enabled: false,
          template_repository: draft.template,
          autograding_enabled: draft.autograding,
          tests: Enum.map(draft.tests, &Map.from_struct/1)
        }

        result =
          if socket.assigns.assignment_record do
            AssignmentsContext.update_assignment(
              socket.assigns.current_user,
              socket.assigns.assignment_record.id,
              attrs
            )
          else
            AssignmentsContext.create_assignment(
              socket.assigns.current_user,
              socket.assigns.classroom_record.id,
              attrs
            )
          end

        case result do
          {:ok, assignment} ->
            {:noreply,
             socket
             |> assign(error: nil)
             |> push_patch(
               to: "/classrooms/#{socket.assigns.classroom.slug}/assignments/#{assignment.slug}"
             )}

          {:error, _reason} ->
            {:noreply,
             assign(socket,
               error: gettext("Could not save the assignment. Check the form and try again.")
             )}
        end

      {:error, _reason} ->
        {:noreply, invalid_deadline(socket)}
    end
  end

  defp invalid_deadline(socket) do
    changeset =
      socket.assigns.assignment_form.source
      |> Ecto.Changeset.add_error(:deadline, gettext("Choose a valid local deadline."))
      |> Map.put(:action, :insert)

    assign(socket, assignment_form: to_form(changeset, as: :assignment))
  end

  defp local_deadline(nil), do: {:ok, nil}

  defp local_deadline(%NaiveDateTime{} = deadline),
    do: GradePush.Time.local_to_utc(NaiveDateTime.to_iso8601(deadline))

  defp local_deadline(deadline) when is_binary(deadline),
    do: GradePush.Time.local_to_utc(deadline)

  defp extension_deadline(value) when value in [nil, ""], do: {:ok, nil}

  defp extension_deadline(value) when is_binary(value) do
    with {:ok, deadline} <- GradePush.Time.local_to_utc(value) do
      {:ok, DateTime.from_unix!(DateTime.to_unix(deadline, :microsecond), :microsecond)}
    end
  end

  defp extension_deadline(_), do: {:error, :invalid_datetime}

  defp assign_real_assignment_form(socket, params, action) do
    params =
      params |> preserve_locked_assignment_fields(socket.assigns) |> Map.put("cutoff", "false")

    templates =
      include_locked_template(socket.assigns.templates, socket.assigns.assignment_record)

    changeset = AssignmentDraft.changeset(%AssignmentDraft{}, params, templates)
    form = to_form(%{changeset | action: action}, as: :assignment)
    assign(socket, assignment_form: form, assignment_params: params, error: nil)
  end

  defp preserve_locked_assignment_fields(params, %{
         assignment: %{submitted: count},
         assignment_record: record
       })
       when count > 0 do
    locked =
      record
      |> TeacherWorkspace.assignment_params()
      |> Map.take(~w(kind team_mode team_size template autograding tests))

    Map.merge(params, locked)
  end

  defp preserve_locked_assignment_fields(params, _assigns), do: params

  defp assignment_changeset(params, templates),
    do: AssignmentDraft.changeset(%AssignmentDraft{}, params, templates)

  defp reload_real_workspace(socket, notice) do
    modal =
      if modal?(socket.assigns.modal, "teams") or modal?(socket.assigns.modal, "test_results"),
        do: socket.assigns.modal

    {:noreply, socket} =
      handle_real_params(socket.assigns.route_params, socket.assigns.path, socket)

    {:noreply, assign(socket, modal: modal, notice: notice)}
  end

  defp refreshable_workspace?(%{live_action: action, modal: modal}) do
    action not in [:new_assignment, :edit_assignment] and
      (is_nil(modal) or modal?(modal, "test_results"))
  end

  defp subscribe_to_workspace(socket, classroom, assignment) do
    topics =
      if connected?(socket) do
        [
          if(classroom, do: "classroom:#{classroom.id}"),
          if(assignment, do: "assignment:#{assignment.id}")
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
      else
        []
      end

    current_topics = Map.get(socket.assigns, :subscribed_topics, [])
    Enum.each(current_topics -- topics, &Phoenix.PubSub.unsubscribe(GradePush.PubSub, &1))
    Enum.each(topics -- current_topics, &Phoenix.PubSub.subscribe(GradePush.PubSub, &1))
    assign(socket, subscribed_topics: topics)
  end

  defp refresh_assignment_details(socket, query, filter) do
    details =
      cond do
        is_nil(socket.assigns.assignment) ->
          nil

        socket.assigns.preview? ->
          PreviewAssignments.details(
            socket.assigns.assignment,
            socket.assigns.classroom,
            query,
            filter,
            socket.assigns.locale
          )

        true ->
          TeacherWorkspace.details(
            socket.assigns.assignment,
            socket.assigns.classroom,
            socket.assigns.teams,
            socket.assigns.assignment_subjects,
            socket.assigns.assignment_activity,
            query,
            filter,
            socket.assigns.locale
          )
      end

    assign(socket, assignment_details: details)
  end

  defp classroom_organizations(organizations) do
    Enum.filter(organizations, fn
      organization when is_map(organization) -> Map.get(organization, :status) == "active"
      _preview_organization -> true
    end)
  end

  defp institution_name do
    case Accounts.institution() do
      %{name: name} when is_binary(name) -> name
      _ -> ""
    end
  end

  defp template_name(%{full_name: name}), do: name
  defp template_name(%{name: name}), do: name
  defp template_name(name) when is_binary(name), do: name

  defp unwrap({:ok, value}, _default), do: value
  defp unwrap(value, _default) when not is_tuple(value), do: value
  defp unwrap({:error, _reason}, default), do: default

  defp parse_id(value) do
    case parse_id_result(value) do
      {:ok, id} -> id
      _ -> nil
    end
  end

  defp parse_id_result(value) when is_integer(value), do: {:ok, value}

  defp parse_id_result(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> {:error, :invalid_id}
    end
  end

  defp parse_id_result(_), do: {:error, :invalid_id}

  defp absolute_url(path) do
    GradePushWeb.Endpoint.url()
    |> URI.merge(path)
    |> URI.to_string()
  end

  defp save_class(socket, params, name) do
    semester =
      case Ecto.Enum.cast_value(GradePush.Classrooms.Classroom, :semester, params["semester"]) do
        {:ok, value} -> value
        :error -> nil
      end

    changes = %{
      title: %{en: name, fr: name},
      description: %{en: params["description"], fr: params["description"]},
      code: params["code"],
      semester: semester,
      academic_year: params["academic_year"]
    }

    if elem(socket.assigns.modal, 0) == "edit" do
      {:noreply, socket |> update_class(changes) |> assign(modal: nil, error: nil)}
    else
      classroom =
        Fixtures.classroom("new")
        |> Map.merge(changes)
        |> Map.merge(%{
          slug: "class-#{length(socket.assigns.classes) + 1}",
          members: [],
          teachers: [hd(Fixtures.teachers())]
        })

      {:noreply,
       socket
       |> assign(classes: socket.assigns.classes ++ [classroom])
       |> push_patch(to: "/classrooms/#{classroom.slug}")}
    end
  end

  defp assign_assignment_form(socket, params, action \\ nil) do
    changeset =
      AssignmentEditing.changeset(
        params,
        socket.assigns.assignment,
        socket.assigns.classroom,
        socket.assigns.locale
      )

    form = to_form(%{changeset | action: action}, as: :assignment)
    assign(socket, assignment_form: form, assignment_params: params)
  end

  defp save_assignment(socket, draft) do
    existing = socket.assigns.assignment
    classroom = socket.assigns.classroom
    key = if existing, do: existing.key, else: "assignment-#{System.unique_integer([:positive])}"
    assignment = AssignmentEditing.materialize(draft, existing, classroom, key)

    assignments =
      Enum.reject(socket.assigns.assignments, &(&1.classroom == classroom.slug and &1.key == key)) ++
        [assignment]

    count = Enum.count(assignments, &(&1.classroom == classroom.slug))

    {:noreply,
     socket
     |> assign(assignments: assignments)
     |> update_class(%{assignments: count})
     |> push_patch(to: "/classrooms/#{classroom.slug}/assignments/#{key}")}
  end

  defp classroom_assignments(assignments, classroom),
    do: Enum.filter(assignments, &(&1.classroom == classroom.slug))

  defp update_class(socket, changes) do
    classroom = Map.merge(socket.assigns.classroom, changes)

    classes =
      Enum.map(socket.assigns.classes, &if(&1.slug == classroom.slug, do: classroom, else: &1))

    assign(socket, classroom: classroom, classes: classes)
  end

  defp available_teachers(%{preview?: true, classroom: classroom}) do
    Fixtures.colleagues()
    |> Enum.reject(fn teacher -> Enum.any?(classroom.teachers, &(&1.name == teacher.name)) end)
  end

  defp available_teachers(assigns) do
    case Accounts.institution_teachers(assigns.current_user) do
      {:ok, teachers} ->
        classroom_ids = MapSet.new(assigns.classroom.teachers, & &1.id)

        teachers
        |> Enum.reject(
          &(&1.id == assigns.current_user.id or MapSet.member?(classroom_ids, &1.id))
        )
        |> Enum.map(&TeacherWorkspace.teacher/1)

      _ ->
        []
    end
  end

  defp unassigned_students(members, teams) do
    assigned_ids =
      Enum.reduce(teams, MapSet.new(), fn team, ids ->
        MapSet.union(ids, team.member_ids)
      end)

    Enum.reject(members, &MapSet.member?(assigned_ids, &1.id))
  end

  defp teacher_team_assignment?(%{
         preview?: false,
         assignment_record: %{kind: "team"}
       }),
       do: true

  defp teacher_team_assignment?(_assigns), do: false

  defp team_action_notice("remove"),
    do: gettext("Student removed. GitHub access will be updated.")

  defp team_action_notice("delete"), do: gettext("Team deleted. GitHub access will be updated.")

  defp team_error(:team_name_required), do: gettext("Enter a team name.")

  defp team_error(%Ecto.Changeset{errors: errors}) do
    if Keyword.has_key?(errors, :name),
      do: gettext("Choose a unique team name of at most 120 characters."),
      else: gettext("Could not update teams. Check the selection and try again.")
  end

  defp team_error(:team_full), do: gettext("This team has reached its member limit.")
  defp team_error(:already_in_team), do: gettext("This student already belongs to a team.")

  defp team_error(:student_not_enrolled),
    do: gettext("This student is no longer in the classroom.")

  defp team_error(_), do: gettext("Could not update teams. Check the selection and try again.")

  defp teacher_option_value(%{id: id}) when not is_nil(id), do: id
  defp teacher_option_value(%{name: name}), do: name
  defp teacher_option_value(value), do: value

  defp teacher_remove_id(%{id: id}) when not is_nil(id), do: "teacher-remove-#{id}"
  defp teacher_remove_id(%{initials: initials}), do: "teacher-remove-#{initials}"

  defp classroom_organization_locked?(%{
         preview?: false,
         modal: {"edit", _},
         classroom: classroom
       })
       when not is_nil(classroom), do: classroom.assignments > 0

  defp classroom_organization_locked?(_assigns), do: false

  defp teacher_name(%{name: name}), do: name
  defp teacher_name(name), do: name

  defp not_current_teacher?(teacher, %{preview?: true, user: user}),
    do: teacher.name != user.name

  defp not_current_teacher?(teacher, %{user: user}), do: teacher.id != user.id

  defp preview_classes do
    Enum.map(Fixtures.classrooms(), fn classroom ->
      students =
        Fixtures.students()
        |> Enum.take(classroom.students)
        |> Enum.with_index(1)
        |> Enum.map(fn {student, index} ->
          Map.put(student, :identifier, "260#{1000 + index}")
        end)

      Map.put(classroom, :members, students)
    end)
  end

  defp visible_students(classroom, query) do
    Enum.filter(classroom.members, fn student ->
      text = "#{student.name} #{student.handle} #{student.identifier}"
      String.contains?(String.downcase(text), String.downcase(query))
    end)
  end

  defp local(text, locale), do: Map.fetch!(text, String.to_existing_atom(locale))

  defp editor_title(:new_assignment, _classroom, _assignment, _locale),
    do: gettext("New assignment")

  defp editor_title(:settings, _classroom, _assignment, _locale), do: gettext("Settings")
  defp editor_title(:signed_out, _classroom, _assignment, _locale), do: gettext("See you soon")

  defp editor_title(:edit_assignment, _classroom, _assignment, _locale),
    do: gettext("Edit assignment")

  defp editor_title(_action, classroom, assignment, locale),
    do: preview_title(classroom, assignment, locale)

  defp preview_title(_classroom, assignment, locale) when not is_nil(assignment),
    do: local(assignment.title, locale)

  defp preview_title(classroom, _assignment, locale) when not is_nil(classroom),
    do: local(classroom.title, locale)

  defp preview_title(_classroom, _assignment, _locale), do: gettext("My classrooms")
  defp modal?(nil, _kind), do: false
  defp modal?({kind, _}, kind), do: true
  defp modal?(_, _), do: false

  defp modal_resource_available?(kind, _assigns)
       when kind in ["create", "connect_organization"],
       do: true

  defp modal_resource_available?(kind, assigns)
       when kind in ["edit", "invite", "teachers", "remove"],
       do: not is_nil(assigns.classroom)

  defp modal_resource_available?("clone_all", assigns), do: not is_nil(assigns.classroom)

  defp modal_resource_available?("assignment_invite", assigns),
    do: not is_nil(assigns.assignment)

  defp modal_resource_available?("teams", assigns),
    do: teacher_team_assignment?(assigns)

  defp modal_resource_available?("test_results", assigns),
    do: not assigns.preview? and match?(%{autograding_enabled: true}, assigns.assignment_record)

  defp modal_resource_available?("deadline_extension", assigns),
    do:
      not assigns.preview? and not is_nil(assigns.assignment_record) and
        not is_nil(assigns.assignment_record.deadline_at)

  defp modal_resource_available?(_, _assigns), do: false

  defp modal_title({"create", _}), do: gettext("Create a classroom")
  defp modal_title({"edit", _}), do: gettext("Edit classroom")
  defp modal_title({"invite", _}), do: gettext("Invite students")
  defp modal_title({"teachers", _}), do: gettext("Manage teachers")
  defp modal_title({"remove", _}), do: gettext("Remove student?")
  defp modal_title({"assignment_invite", _}), do: gettext("Share assignment")
  defp modal_title({"clone_all", _}), do: gettext("Clone all locally")
  defp modal_title({"connect_organization", _}), do: gettext("Connect an organization")
  defp modal_title({"teams", _}), do: gettext("Manage teams")
  defp modal_title({"remove_assignment_test", _}), do: gettext("Remove test?")
  defp modal_title({"test_results", _}), do: gettext("Automatic test results")
  defp modal_title({"deadline_extension", _}), do: gettext("Revise submission deadline")

  defp editable_assignment_tests?(%{preview?: false, assignment: %{submitted: count}})
       when count > 0,
       do: false

  defp editable_assignment_tests?(%{live_action: action, assignment_form: %Phoenix.HTML.Form{}})
       when action in [:new_assignment, :edit_assignment], do: true

  defp editable_assignment_tests?(_assigns), do: false

  defp assignment_test_at(socket, index) do
    socket.assigns.assignment_form.source
    |> Ecto.Changeset.get_field(:tests, [])
    |> Enum.at(index)
  end

  defp editing_value(assigns, key) do
    params = Map.get(assigns, :class_form_params, %{})
    field = if key == :title, do: "name", else: Atom.to_string(key)

    if Map.has_key?(params, field) do
      params[field]
    else
      original_editing_value(assigns, key)
    end
  end

  defp original_editing_value(assigns, key) do
    if modal?(assigns.modal, "edit") do
      value = Map.get(assigns.classroom, key)
      if is_map(value), do: local(value, assigns.locale), else: value
    else
      ""
    end
  end

  defp selected_organization(assigns) do
    value = editing_value(assigns, :github_connection_id)

    if modal?(assigns.modal, "create") and value in [nil, ""] do
      case List.first(classroom_organizations(assigns.organizations)) do
        %{id: id} -> id
        organization -> organization
      end
    else
      value
    end
  end

  defp selected_student(classroom, {"remove", handle}),
    do: Enum.find(classroom.members, &(&1.handle == handle))

  defp extension_set?(%{modal: {"deadline_extension", subject_id}, assignment_subjects: subjects}) do
    case Enum.find(subjects, &(&1.id == subject_id)) do
      %{extension_until: %DateTime{}} -> true
      _ -> false
    end
  end

  defp extension_set?(_assigns), do: false

  defp locale_url("/teacher/settings" = path, _tab, _view, section, locale),
    do: path <> "?" <> URI.encode_query(%{locale: locale, section: section})

  defp locale_url(path, tab, view, _section, locale),
    do: path <> "?" <> URI.encode_query(%{locale: locale, tab: tab, view: view})

  defp open_modal(kind), do: JS.push_focus() |> JS.push("open", value: %{kind: kind})
end
