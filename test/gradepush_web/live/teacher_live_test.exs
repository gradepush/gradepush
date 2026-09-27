defmodule GradePushWeb.TeacherLiveTest do
  use GradePushWeb.ConnCase

  import Phoenix.LiveViewTest

  test "classroom term validation identifies both fields and returns focus", %{conn: conn} do
    {:ok, view, _} = live(conn, "/classrooms")
    view |> element("button", "Create a classroom") |> render_click()

    view
    |> form("#class-form", class: %{name: "Test", semester: "fall", academic_year: ""})
    |> render_submit()

    for field <- ~w(semester academic_year) do
      assert has_element?(
               view,
               "[name='class[#{field}]'][aria-invalid='true'][aria-describedby='class-modal-error']"
             )
    end

    assert_push_event(view, "focus-invalid", %{id: "class-form"})
    assert has_element?(view, "#class-modal-error", "Choose both a semester and a year")
  end

  test "the new entry point limits navigation to classrooms and two class sections", %{conn: conn} do
    {:ok, view, _} = live(conn, "/classrooms")
    assert has_element?(view, "h1", "My classrooms")

    for slug <- ~w(programming web-development data-structures) do
      assert has_element?(view, ".cp-class-card[href='/classrooms/#{slug}']")
    end

    refute has_element?(view, ".sidebar")

    view |> element("a.cp-class-card[href='/classrooms/programming']") |> render_click()
    assert has_element?(view, "h1", "Programming I")
    assert has_element?(view, ".cp-tabs a[aria-current='page']", "Assignments")
    refute has_element?(view, ".cp-tabs a", "Settings")

    assert has_element?(
             view,
             ".cp-toolbar a[href='/classrooms/programming/assignments/new']",
             "New assignment"
           )

    view |> element(".cp-tabs a", "Students") |> render_click()
    assert_patch(view, "/classrooms/programming?tab=students")
    assert has_element?(view, ".cp-tabs a[aria-current='page']", "Students")
    assert has_element?(view, "#student-amelie-fortin")
  end

  test "student removal requires confirmation and stays scoped to its classroom", %{conn: conn} do
    {:ok, view, _} = live(conn, "/classrooms/programming?tab=students")
    view |> element("#student-amelie-fortin button") |> render_click()
    assert has_element?(view, "[role='dialog']", "repositories and GitHub access will be kept")
    assert has_element?(view, "#student-amelie-fortin")
    render_click(view, "close")
    assert has_element?(view, "#student-amelie-fortin")

    view |> element("#student-amelie-fortin button") |> render_click()
    view |> element("button[phx-click='remove_student']") |> render_click()
    refute has_element?(view, "#student-amelie-fortin")
    assert has_element?(view, ".cp-tabs a", "27")
    render_patch(view, "/classrooms/web-development?tab=students")
    assert has_element?(view, "#student-amelie-fortin")
    render_patch(view, "/classrooms/programming?tab=students")
    refute has_element?(view, "#student-amelie-fortin")
  end

  test "student search matches identity and handles no results", %{conn: conn} do
    {:ok, view, _} = live(conn, "/classrooms/programming?tab=students")
    view |> form("form[role='search']", query: "2601001") |> render_change()
    assert has_element?(view, "#student-amelie-fortin")
    refute has_element?(view, "#student-max-fortin")
    view |> form("form[role='search']", query: "no-match") |> render_change()
    assert has_element?(view, ".cp-empty", "No matching students")
  end

  test "classroom forms validate and preserve changes through navigation", %{conn: conn} do
    {:ok, view, _} = live(conn, "/classrooms?scenario=empty")
    view |> element(".cp-heading button") |> render_click()
    view |> form("#class-form", class: %{name: "   "}) |> render_submit()
    assert has_element?(view, "[role='alert']", "Enter a classroom name")

    view
    |> form("#class-form", class: %{name: "Algorithms", code: "420-500", description: "Graphs"})
    |> render_submit()

    assert_patch(view, "/classrooms/class-4")
    assert has_element?(view, "h1", "Algorithms")
    assert has_element?(view, ".cp-empty", "No assignments yet")
    view |> element(".cp-class-heading button") |> render_click()
    view |> form("#class-form", class: %{name: "Algorithms II"}) |> render_submit()
    view |> element(".cp-breadcrumbs a[href='/classrooms']") |> render_click()
    assert has_element?(view, ".cp-class-card", "Algorithms II")
  end

  test "semester and year are paired, editable and group classrooms chronologically", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/classrooms?locale=fr")
    view |> element(".cp-heading button") |> render_click()
    refute has_element?(view, "input[name='class[session]']")

    view
    |> form("#class-form", class: %{name: "Algorithmique", semester: "winter"})
    |> render_submit()

    assert has_element?(view, "[role='alert']")
    assert has_element?(view, "input[name='class[name]'][value='Algorithmique']")
    view |> form("#class-form", class: %{academic_year: "2027"}) |> render_submit()
    assert has_element?(view, ".cp-class-session", "Hiver 2027")
    view |> element(".cp-breadcrumbs a[href='/classrooms']") |> render_click()
    assert has_element?(view, ".cp-term-group:first-of-type h2", "Hiver 2027")
    assert has_element?(view, ".cp-term-group:first-of-type a[href='/classrooms/class-4']")
    view |> element("a[href='/classrooms/class-4']") |> render_click()
    view |> element(".cp-class-heading button") |> render_click()
    assert has_element?(view, "select[name='class[semester]'] option[value='winter'][selected]")

    assert has_element?(view, "input[type='text'][name='class[academic_year]'][value='2027']")

    view |> form("#class-form", class: %{semester: "", academic_year: ""}) |> render_submit()
    refute has_element?(view, ".cp-class-session")
    view |> element(".cp-class-heading button") |> render_click()
    assert has_element?(view, "select[name='class[semester]']")
    render_click(view, "close")
    view |> element(".cp-breadcrumbs a[href='/classrooms']") |> render_click()
    assert has_element?(view, ".cp-term-group:last-of-type h2", "Sans session")
  end

  test "breadcrumbs navigate from assignment editing through its parents", %{conn: conn} do
    {:ok, view, _} = live(conn, "/classrooms/programming/assignments/cli/edit")
    assert has_element?(view, ".cp-breadcrumbs [aria-current='page']", "Edit assignment")

    view
    |> element(".cp-breadcrumbs a[href='/classrooms/programming/assignments/cli']")
    |> render_click()

    assert_patch(view, "/classrooms/programming/assignments/cli")
    assert has_element?(view, ".cp-breadcrumbs [aria-current='page']", "CLI Argument Parser")
    view |> element(".cp-breadcrumbs a[href='/classrooms/programming']") |> render_click()
    assert has_element?(view, ".cp-breadcrumbs [aria-current='page']", "Programming I")
    view |> element(".cp-toolbar a") |> render_click()
    assert has_element?(view, ".cp-breadcrumbs [aria-current='page']", "New assignment")
    refute has_element?(view, ".cp-breadcrumbs a[href*='/assignments/']")
    view |> element(".cp-breadcrumbs a[href='/classrooms']") |> render_click()
    assert has_element?(view, "h1", "My classrooms")
  end

  test "colleagues have equal roles and the last teacher cannot be removed", %{conn: conn} do
    {:ok, view, _} = live(conn, "/classrooms/data-structures")
    view |> element(".cp-teachers-link") |> render_click()
    assert has_element?(view, "[role='dialog']", "same permissions")
    refute has_element?(view, ".cp-teacher-list button")
    render_click(view, "remove_teacher", %{"name" => "Jordan Rioux"})
    assert has_element?(view, ".cp-teacher-list", "Jordan Rioux")
    render_click(view, "request_teacher_removal", %{"teacher" => "Jordan Rioux"})
    refute has_element?(view, "#teacher-removal-confirmation")
    view |> form("form[phx-submit='add_teacher']", teacher: "Alex Nguyen") |> render_submit()
    assert has_element?(view, ".cp-teacher-list", "Alex Nguyen")
    view |> element("#teacher-remove-AN") |> render_click()
    assert has_element?(view, ".cp-teacher-list", "Alex Nguyen")
    view |> element("#teacher-removal-confirmation .cp-danger") |> render_click()
    refute has_element?(view, ".cp-teacher-list", "Alex Nguyen")
  end

  test "teacher removal requires confirmation and closing or cancelling discards it", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/classrooms/programming")
    view |> element(".cp-teachers-link") |> render_click()
    render_click(view, "remove_teacher", %{"name" => "Camille Bergeron"})
    assert has_element?(view, ".cp-teacher-list", "Camille Bergeron")
    view |> element("#teacher-remove-CB") |> render_click()

    assert has_element?(
             view,
             "#teacher-removal-confirmation",
             "Remove Camille Bergeron from this classroom?"
           )

    view |> element("#cancel-teacher-removal") |> render_click()
    refute has_element?(view, "#teacher-removal-confirmation")
    assert has_element?(view, ".cp-teacher-list", "Camille Bergeron")
    render_click(view, "remove_teacher", %{})
    assert has_element?(view, ".cp-teacher-list", "Camille Bergeron")
    view |> element("#teacher-remove-CB") |> render_click()
    render_click(view, "close")
    view |> element(".cp-teachers-link") |> render_click()
    refute has_element?(view, "#teacher-removal-confirmation")
    view |> element("#teacher-remove-CB") |> render_click()
    view |> element("#teacher-removal-confirmation .cp-danger") |> render_click()
    refute has_element?(view, ".cp-teacher-list", "Camille Bergeron")
    assert has_element?(view, "#class-dialog")
    render_patch(view, "/classrooms/web-development")
    view |> element(".cp-teachers-link") |> render_click()
    assert has_element?(view, ".cp-teacher-list", "Camille Bergeron")
  end

  test "French deep links and unknown classes render without exposing the old dashboard", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/classrooms/programming?tab=students&locale=fr")
    assert has_element?(view, ".cp-tabs a[aria-current='page']", "Étudiants")
    assert has_element?(view, ".cp-student-labels", "Matricule")
    {:ok, view, _} = live(conn, "/classrooms/unknown")
    assert has_element?(view, "h1", "Classroom not found")
    refute has_element?(view, ".sidebar")
  end

  test "every assignment opens in its classroom and configured terms are displayed", %{conn: conn} do
    {:ok, view, html} = live(conn, "/classrooms")
    assert html =~ "Fall 2026"

    for {classroom, keys} <- [
          {"programming", ~w(cli loops functions)},
          {"web-development", ~w(portfolio)},
          {"data-structures", ~w(linked-list)}
        ] do
      render_patch(view, "/classrooms/#{classroom}")
      assert has_element?(view, ".cp-class-session")

      for key <- keys do
        view
        |> element("a.cp-assignment[href='/classrooms/#{classroom}/assignments/#{key}']")
        |> render_click()

        assert has_element?(view, ".cp-instructions")
        assert has_element?(view, "#assignment-submissions-title")
        view |> element(".cp-breadcrumbs a[href='/classrooms/#{classroom}']") |> render_click()
        assert_patch(view, "/classrooms/#{classroom}")
      end
    end
  end

  test "assignment progress includes unaccepted students and distinguishes unused repositories",
       %{conn: conn} do
    {:ok, view, _} = live(conn, "/classrooms/programming/assignments/cli")
    assert has_element?(view, ".cp-submission-table thead", "Test score")

    assert has_element?(
             view,
             "#submission-mia-leduc .cp-push-cell .cp-dash[aria-label='No pushes']"
           )

    refute has_element?(view, "#submission-mia-leduc button")

    assert has_element?(
             view,
             "#submission-maude-gauthier .cp-push-cell .cp-dash[aria-label='No pushes']"
           )

    assert has_element?(view, "#submission-maude-gauthier button[disabled]")

    view |> form("#submission-search", status: "not_accepted", query: "") |> render_change()
    assert has_element?(view, "#submission-mia-leduc")
    refute has_element?(view, "#submission-amelie-fortin")
    view |> form("#submission-search", status: "all", query: "2601001") |> render_change()
    assert has_element?(view, "#submission-amelie-fortin")
    refute has_element?(view, "#submission-mia-leduc")
  end

  test "late work and team repositories use their own assignment data", %{conn: conn} do
    {:ok, view, _} = live(conn, "/classrooms/programming/assignments/loops")
    refute has_element?(view, ".cp-submission-table thead", "Test score")
    view |> form("#submission-search", status: "late", query: "") |> render_change()
    assert has_element?(view, "#submission-max-fortin", "Sep 19")
    refute has_element?(view, "#submission-amelie-fortin")
    render_patch(view, "/classrooms/data-structures/assignments/linked-list")
    assert has_element?(view, "#submission-team-3")
    refute has_element?(view, "#submission-team-4")

    assert has_element?(
             view,
             "#submission-team-1 a[href='https://github.com/max-fortin']",
             "Maxime Fortin"
           )

    view |> form("#submission-search", status: "all", query: "2601002") |> render_change()
    assert has_element?(view, "#submission-team-1")
    refute has_element?(view, "#submission-team-2")
    render_patch(view, "/classrooms/programming/assignments/functions")
    assert has_element?(view, ".cp-empty", "No teams yet")
  end

  test "assignment invitations are explicit examples and cross-class URLs do not resolve", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/classrooms/programming/assignments/cli")
    view |> element(".cp-assignment-heading button") |> render_click()

    assert has_element?(
             view,
             "[role='dialog'] input[value='https://gradepush.example/join/assignment/cli']"
           )

    assert has_element?(view, "[role='dialog']", "Invitations are not active")
    render_patch(view, "/classrooms/web-development/assignments/cli")
    assert has_element?(view, "h1", "Assignment not found")
    refute has_element?(view, ".cp-submission-table")
  end

  test "submission columns show activity and weighted scores without duplicate progress", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/classrooms/programming/assignments/cli")
    refute has_element?(view, ".cp-submission-table thead", "Progress")
    refute render(view) =~ "Same scale for everyone"
    assert has_element?(view, "#submission-camille-roy .cp-test-score", "60")
    assert has_element?(view, "#submission-camille-roy .cp-test-score", "100")
    assert has_element?(view, "#submission-amelie-fortin svg[role='img']")
    refute has_element?(view, "#submission-maude-gauthier svg")

    assert has_element?(
             view,
             "#submission-amelie-fortin a[href='https://github.com/amelie-fortin'][rel='noopener noreferrer']"
           )

    view |> element(".cp-assignment-tabs a", "Tests") |> render_click()
    assert_patch(view, "/classrooms/programming/assignments/cli?view=tests")
    assert has_element?(view, "#test-catalog-title", "Automatic tests")
    assert has_element?(view, ".cp-test-list li", "40 points")
    refute has_element?(view, ".cp-submission-table")
    view |> element(".cp-assignment-tabs a", "Submissions") |> render_click()
    assert has_element?(view, ".cp-submission-table")
  end

  test "tests deep link and copy feedback are localized and non-destructive", %{conn: conn} do
    {:ok, view, _} = live(conn, "/classrooms/programming/assignments/loops?view=tests&locale=fr")
    assert has_element?(view, ".cp-empty", "Aucun test automatique")
    assert has_element?(view, ".cp-language[href*='view=tests']")
    view |> element(".cp-assignment-heading button") |> render_click()

    assert has_element?(
             view,
             "button[phx-hook='CopyInvitation'][data-copy='https://gradepush.example/join/assignment/loops']"
           )

    render_hook(view, "invitation_copied", %{"ok" => true})
    assert has_element?(view, "[role='status']", "Lien copié")
    render_hook(view, "invitation_copied", %{"ok" => false})
    assert has_element?(view, "[role='status']", "manuellement")
  end
end
