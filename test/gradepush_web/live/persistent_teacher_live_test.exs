defmodule GradePushWeb.PersistentTeacherLiveTest do
  use GradePushWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures

  alias GradePush.{Assignments, Classrooms}

  test "overlapping classroom and assignment notifications reload the workspace once", %{
    conn: conn
  } do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    assignment = assignment_fixture(teacher, classroom)

    {:ok, view, _} =
      conn
      |> log_in_user(teacher)
      |> live("/classrooms/#{classroom.slug}/assignments/#{assignment.slug}")

    counter = :atomics.new(1, [])
    handler = "workspace-queries-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:grade_push, :repo, :query],
      &__MODULE__.count_workspace_query/4,
      {view.pid, counter}
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    send(view.pid, {:submission_changed, 1})
    wait_for_refresh(view)
    single_refresh_queries = :atomics.get(counter, 1)
    assert single_refresh_queries > 0
    :atomics.put(counter, 1, 0)

    assignment |> Ecto.Changeset.change(title: "Updated lab") |> GradePush.Repo.update!()
    :sys.suspend(view.pid)
    send(view.pid, {:assignment_accepted, 1})
    send(view.pid, {:submission_changed, 1})
    :sys.resume(view.pid)
    wait_for_refresh(view)

    assert has_element?(view, "h1", "Updated lab")
    assert :atomics.get(counter, 1) == single_refresh_queries

    send(view.pid, {:submission_changed, 1})
    render_patch(view, "/classrooms/#{classroom.slug}/assignments/#{assignment.slug}/edit")
    view |> form("#assignment-form", assignment: %{title: "Unsaved draft"}) |> render_change()
    wait_for_refresh(view)
    assert has_element?(view, "input[name='assignment[title]'][value='Unsaved draft']")
  end

  def count_workspace_query(_event, _measurements, _metadata, {pid, counter}) do
    if self() == pid, do: :atomics.add_get(counter, 1, 1)
  end

  defp wait_for_refresh(view) do
    Process.sleep(75)
    render(view)
    Process.sleep(75)
    render(view)
  end

  test "creating a classroom selects the first connected organization", %{conn: conn} do
    %{user: teacher} = bootstrap_fixture()
    existing = classroom_fixture(teacher)
    {:ok, view, _} = conn |> log_in_user(teacher) |> live("/classrooms")
    view |> element("button", "Create a classroom") |> render_click()

    assert has_element?(
             view,
             "select[name='class[github_connection_id]'] option[value='#{existing.github_connection_id}'][selected]"
           )

    view
    |> form("#class-form", class: %{name: "Default organization", code: "CS-101"})
    |> render_submit()

    {:ok, classrooms} = Classrooms.list_classrooms(teacher)
    classroom = Enum.find(classrooms, &(&1.title == "Default organization"))
    assert classroom.github_connection_id == existing.github_connection_id
  end

  test "editing a legacy classroom preserves its term until explicitly replaced", %{conn: conn} do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher, %{session: "Cohorte soir 2027–2028"})
    {:ok, view, _} = conn |> log_in_user(teacher) |> live("/classrooms/#{classroom.slug}")
    view |> element(".cp-class-heading button") |> render_click()
    assert has_element?(view, "select[name='class[semester]'] option[value='legacy'][selected]")
    view |> form("#class-form", class: %{name: "Evening class"}) |> render_submit()

    assert {:ok, %{session: "Cohorte soir 2027–2028"}} =
             Classrooms.get_classroom(teacher, classroom.slug)

    view |> element(".cp-class-heading button") |> render_click()
    view |> form("#class-form", class: %{semester: "", academic_year: ""}) |> render_submit()

    assert {:ok, %{session: "", semester: nil, academic_year: nil}} =
             Classrooms.get_classroom(teacher, classroom.slug)
  end

  test "teacher edits persist, assignment drafts survive background events and another teacher is denied",
       %{conn: conn} do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    conn = log_in_user(conn, teacher)
    {:ok, view, html} = live(conn, "/classrooms/#{classroom.slug}")
    assert html =~ classroom.title

    view |> element(".cp-class-heading button") |> render_click()
    assert has_element?(view, "input[type='text'][name='class[academic_year]']")

    view
    |> form("#class-form",
      class: %{name: "Algorithms", semester: "winter", academic_year: "26"}
    )
    |> render_submit()

    assert {:ok, %{title: "Algorithms", semester: "winter", academic_year: "26"}} =
             Classrooms.get_classroom(teacher, classroom.slug)

    view |> element("a", "New assignment") |> render_click()

    view
    |> form("#assignment-form",
      assignment: %{
        title: "Sorting lab",
        instructions: "## Sort a list",
        deadline: "2026-10-15T16:30"
      }
    )
    |> render_change()

    send(view.pid, {:student_joined, 999})
    assert has_element?(view, "input[name='assignment[title]'][value='Sorting lab']")
    view |> form("#assignment-form") |> render_submit()
    path = assert_patch(view)
    assert has_element?(view, "h1", "Sorting lab")
    {:ok, [assignment]} = Assignments.list_assignments(teacher, classroom.id)
    assert assignment.deadline_at == ~U[2026-10-15 20:30:00.000000Z]
    {:ok, _, refreshed} = live(conn, path)
    assert refreshed =~ "Sorting lab"

    outsider = user_fixture()
    teacher_membership_fixture(outsider)
    {:ok, _, denied} = build_conn() |> log_in_user(outsider) |> live(path)
    refute denied =~ "Sorting lab"
    refute denied =~ "Algorithms"
  end

  test "a teacher sees declared student identity and removal preserves accepted work", %{
    conn: conn
  } do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    assignment = assignment_fixture(teacher, classroom)
    student = user_fixture()
    {:ok, invite} = Assignments.create_assignment_invitation(teacher, assignment.id)

    {:ok, %{subject: subject}} =
      Assignments.accept_assignment_invitation(student, invite.token, %{
        name: "Camille Student",
        student_id: "2026001"
      })

    {:ok, view, _} =
      conn |> log_in_user(teacher) |> live("/classrooms/#{classroom.slug}?tab=students")

    assert has_element?(view, "#student-#{student.login}", "Camille Student")
    assert has_element?(view, "#student-#{student.login}", "2026001")
    view |> element("#student-#{student.login} button") |> render_click()
    assert has_element?(view, "[role='dialog']")
    assert {:ok, [_]} = Classrooms.list_students(teacher, classroom.id)
    view |> element("button[phx-click='remove_student']") |> render_click()
    assert {:ok, []} = Classrooms.list_students(teacher, classroom.id)
    assert {:ok, [preserved]} = Assignments.list_submissions(teacher, assignment.id)
    assert preserved.id == subject.id
  end

  test "accepted assignment edits preserve controls omitted by the browser", %{conn: conn} do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    assignment = assignment_fixture(teacher, classroom, %{kind: "team", team_size: 4})
    student = user_fixture()
    {:ok, invitation} = Assignments.create_assignment_invitation(teacher, assignment.id)

    {:ok, _} =
      Assignments.accept_assignment_invitation(student, invitation.token, %{
        name: "Camille",
        student_id: "2026001",
        team_name: "Team Blue"
      })

    {:ok, view, _} =
      conn
      |> log_in_user(teacher)
      |> live("/classrooms/#{classroom.slug}/assignments/#{assignment.slug}/edit")

    assert has_element?(view, "fieldset[disabled]")

    render_submit(view, "save_assignment", %{
      "assignment" => %{
        "title" => "Updated team lab",
        "instructions" => "## Updated instructions",
        "deadline" => "2026-10-15T16:30",
        "autograding" => "false"
      }
    })

    assert_patch(view, "/classrooms/#{classroom.slug}/assignments/#{assignment.slug}")
    assert {:ok, updated} = Assignments.get_assignment(teacher, classroom.id, assignment.slug)
    assert updated.title == "Updated team lab"
    assert updated.kind == "team"
    assert updated.team_size == 4
    assert updated.instructions == "## Updated instructions"
    assert DateTime.compare(updated.deadline_at, ~U[2026-10-15 20:30:00Z]) == :eq
  end

  test "colleague management lists teachers once and cancellation preserves classroom staff", %{
    conn: conn
  } do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    colleague = user_fixture(%{name: "Colleague"})
    teacher_membership_fixture(colleague)
    {:ok, _} = Classrooms.add_teacher(teacher, classroom.id, colleague.id)
    {:ok, view, _} = conn |> log_in_user(teacher) |> live("/classrooms/#{classroom.slug}")
    view |> element(".cp-teachers-link") |> render_click()
    assert has_element?(view, "[role='dialog']", "Colleague")
    render_click(view, "close")
    assert {:ok, current} = Classrooms.get_classroom(teacher, classroom.slug)
    assert length(current.teachers) == 2
    assert {:ok, teachers} = GradePush.Accounts.institution_teachers(teacher)
    assert Enum.sort(Enum.map(teachers, & &1.id)) == Enum.sort([teacher.id, colleague.id])
  end
end
