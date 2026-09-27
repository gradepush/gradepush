defmodule GradePushWeb.TeacherLive do
  @moduledoc "Teacher workspace using in-memory preview state until the teaching contexts are connected."
  use GradePushWeb, :live_view

  alias GradePushWeb.AccountComponents
  alias GradePushWeb.AssignmentComponents
  alias GradePushWeb.AssignmentEditor
  alias GradePushWeb.ClassroomComponents
  alias GradePushWeb.Preview.AssignmentEditing
  alias GradePushWeb.Preview.Assignments
  alias GradePushWeb.Preview.Fixtures
  alias GradePushWeb.WorkspaceLayout

  @impl true
  def mount(_params, session, socket) do
    locale = if session["locale"] in ~w(en fr), do: session["locale"], else: "en"
    Gettext.put_locale(GradePushWeb.Gettext, locale)

    classes =
      Enum.map(Fixtures.classrooms(), fn classroom ->
        students =
          Fixtures.students()
          |> Enum.take(classroom.students)
          |> Enum.with_index(1)
          |> Enum.map(fn {student, index} ->
            Map.put(student, :identifier, "260#{1000 + index}")
          end)

        Map.merge(classroom, %{members: students, session: ""})
      end)

    {:ok,
     assign(socket,
       page_title: gettext("My classrooms"),
       locale: locale,
       user: hd(Fixtures.teachers()),
       institution: Fixtures.institution(),
       organizations: Fixtures.organizations(),
       classes: classes,
       assignments: Enum.flat_map(classes, &Assignments.for_classroom(&1.slug)),
       assignment_form: nil,
       assignment_params: %{},
       instructions_preview: false,
       classroom: nil,
       assignment: nil,
       submission_filter: "all",
       assignment_tab: "submissions",
       settings_section: "account",
       copy_status: nil,
       tab: "assignments",
       query: "",
       modal: nil,
       pending_teacher: nil,
       error: nil,
       notice: nil,
       path: "/",
       scenario: nil
     )}
  end

  @impl true
  def handle_params(params, uri, socket) do
    classroom = Enum.find(socket.assigns.classes, &(&1.slug == params["slug"]))
    tab = if params["tab"] == "students", do: "students", else: "assignments"

    assignment =
      Enum.find(
        socket.assigns.assignments,
        &(&1.classroom == params["slug"] and &1.key == params["assignment"])
      )

    editor_params = AssignmentEditing.params(assignment, socket.assigns.locale)

    editor_form =
      if classroom,
        do:
          to_form(
            AssignmentEditing.changeset(
              editor_params,
              assignment,
              classroom,
              socket.assigns.locale
            ),
            as: :assignment
          )

    {:noreply,
     assign(socket,
       classroom: classroom,
       assignment: assignment,
       assignment_form: editor_form,
       assignment_params: editor_params,
       instructions_preview: false,
       assignment_tab: if(params["view"] == "tests", do: "tests", else: "submissions"),
       settings_section:
         if(params["section"] == "organizations", do: "organizations", else: "account"),
       copy_status: nil,
       page_title:
         editor_title(socket.assigns.live_action, classroom, assignment, socket.assigns.locale),
       submission_filter: "all",
       tab: tab,
       path: URI.parse(uri).path,
       scenario: params["scenario"],
       query: "",
       modal: nil,
       pending_teacher: nil,
       notice: nil,
       error: nil
     )}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket),
    do: {:noreply, assign(socket, query: query)}

  def handle_event("filter_submissions", params, socket) do
    {:noreply,
     assign(socket, query: params["query"] || "", submission_filter: params["status"] || "all")}
  end

  def handle_event("open", %{"kind" => kind} = params, socket)
      when kind in ~w(create edit invite teachers remove assignment_invite connect_organization) do
    {:noreply,
     assign(socket,
       modal: {kind, params["handle"]},
       pending_teacher: nil,
       error: nil,
       copy_status: nil
     )}
  end

  def handle_event("invitation_copied", %{"ok" => ok}, socket) do
    status =
      if ok,
        do: gettext("Link copied"),
        else: gettext("Copy failed. Select and copy the link manually.")

    {:noreply, assign(socket, copy_status: status)}
  end

  def handle_event("close", _, socket),
    do: {:noreply, assign(socket, modal: nil, pending_teacher: nil, error: nil)}

  def handle_event("validate_assignment", %{"assignment" => params}, socket) do
    {:noreply, assign_assignment_form(socket, params, :validate)}
  end

  def handle_event("toggle_instructions_preview", _, socket) do
    {:noreply, update(socket, :instructions_preview, &(!&1))}
  end

  def handle_event("add_assignment_test", _, socket) do
    {:noreply,
     assign_assignment_form(socket, AssignmentEditing.add_test(socket.assigns.assignment_params))}
  end

  def handle_event("remove_assignment_test", %{"index" => index}, socket) do
    {:noreply,
     assign_assignment_form(
       socket,
       AssignmentEditing.remove_test(socket.assigns.assignment_params, String.to_integer(index))
     )}
  end

  def handle_event("save_assignment", %{"assignment" => params}, socket) do
    socket = assign_assignment_form(socket, params, :insert)

    case Ecto.Changeset.apply_action(socket.assigns.assignment_form.source, :insert) do
      {:ok, draft} -> save_assignment(socket, draft)
      {:error, _changeset} -> {:noreply, socket}
    end
  end

  def handle_event("save_class", %{"class" => params}, socket) do
    name = String.trim(params["name"] || "")

    if name == "" do
      {:noreply, assign(socket, error: gettext("Enter a classroom name."))}
    else
      save_class(socket, params, name)
    end
  end

  def handle_event("remove_student", _, socket) do
    {"remove", handle} = socket.assigns.modal
    members = Enum.reject(socket.assigns.classroom.members, &(&1.handle == handle))
    socket = update_class(socket, %{members: members, students: length(members)})
    {:noreply, assign(socket, modal: nil, notice: gettext("Student removed from this preview."))}
  end

  def handle_event("add_teacher", %{"teacher" => name}, socket) do
    teacher = Enum.find(available_teachers(socket.assigns.classroom), &(&1.name == name))

    if teacher do
      {:noreply,
       update_class(socket, %{teachers: socket.assigns.classroom.teachers ++ [teacher]})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("request_teacher_removal", %{"name" => name}, socket) do
    teacher =
      if modal?(socket.assigns.modal, "teachers"),
        do:
          Enum.find(
            socket.assigns.classroom.teachers,
            &(&1.name == name and &1.name != socket.assigns.user.name)
          )

    {:noreply, assign(socket, pending_teacher: teacher)}
  end

  def handle_event("cancel_teacher_removal", _, socket),
    do: {:noreply, assign(socket, pending_teacher: nil)}

  def handle_event("remove_teacher", _, socket) do
    teacher = socket.assigns.pending_teacher

    if teacher && modal?(socket.assigns.modal, "teachers") &&
         length(socket.assigns.classroom.teachers) > 1 do
      teachers = Enum.reject(socket.assigns.classroom.teachers, &(&1.name == teacher.name))
      {:noreply, socket |> update_class(%{teachers: teachers}) |> assign(pending_teacher: nil)}
    else
      {:noreply, socket}
    end
  end

  defp save_class(socket, params, name) do
    changes = %{
      title: %{en: name, fr: name},
      description: %{en: params["description"], fr: params["description"]},
      code: params["code"],
      session: String.trim(params["session"] || "")
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

  defp available_teachers(classroom) do
    Fixtures.colleagues()
    |> Enum.reject(fn teacher -> Enum.any?(classroom.teachers, &(&1.name == teacher.name)) end)
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

  defp modal_title({"create", _}), do: gettext("Create a classroom")
  defp modal_title({"edit", _}), do: gettext("Edit classroom")
  defp modal_title({"invite", _}), do: gettext("Invite students")
  defp modal_title({"teachers", _}), do: gettext("Manage teachers")
  defp modal_title({"remove", _}), do: gettext("Remove student?")
  defp modal_title({"assignment_invite", _}), do: gettext("Share assignment")
  defp modal_title({"connect_organization", _}), do: gettext("Connect an organization")

  defp editing_value(assigns, key) do
    if modal?(assigns.modal, "edit") do
      value = Map.fetch!(assigns.classroom, key)
      if is_map(value), do: local(value, assigns.locale), else: value
    else
      ""
    end
  end

  defp selected_student(classroom, {"remove", handle}),
    do: Enum.find(classroom.members, &(&1.handle == handle))

  defp locale_url("/teacher/settings" = path, _tab, _view, section, locale),
    do: path <> "?" <> URI.encode_query(%{locale: locale, section: section})

  defp locale_url(path, tab, view, _section, locale),
    do: path <> "?" <> URI.encode_query(%{locale: locale, tab: tab, view: view})

  defp open_modal(kind), do: JS.push_focus() |> JS.push("open", value: %{kind: kind})
end
