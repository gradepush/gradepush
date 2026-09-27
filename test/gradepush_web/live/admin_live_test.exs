defmodule GradePushWeb.AdminLiveTest do
  use GradePushWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "contexts are reachable without a sign-in screen and locale survives navigation", %{
    conn: conn
  } do
    conn = init_test_session(conn, locale: "fr")
    {:ok, view, _} = live(conn, "/classrooms")

    {:ok, admin, _} =
      view
      |> element("#context-menu a[href='/admin/institution']")
      |> render_click()
      |> follow_redirect(conn)

    assert has_element?(admin, "h1", "Cégep de Sorel-Tracy")
    assert has_element?(admin, "#admin-teacher-camille", "Administrateur")
    assert has_element?(admin, "#context-menu a[aria-current='true']", "Institution")
    refute has_element?(admin, "[data-ui~='sign-in']")

    {:ok, teacher, _} =
      admin
      |> element("#context-menu a[href='/classrooms']")
      |> render_click()
      |> follow_redirect(conn)

    assert has_element?(teacher, "h1", "Mes classes")
  end

  test "institution classes expose only metadata and staffing, with no self-assignment", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/admin/institution?section=classrooms")
    refute has_element?(view, "a[href^='/classrooms/']")
    refute has_element?(view, "[data-ui~='submission-table']")
    refute render(view) =~ "amelie-fortin"
    view |> element("#admin-class-databases button") |> render_click()
    refute has_element?(view, "select[name='staff[teacher]'] option[value='jordan']")
    view |> form("#staff-form", staff: %{teacher: "sophie", replace: "alex"}) |> render_submit()
    refute has_element?(view, "#admin-dialog")
    assert has_element?(view, "#admin-class-databases", "Sophie Gagnon")
    refute has_element?(view, "#admin-class-databases", "Alex Nguyen")
    render_patch(view, "/admin/institution?section=history")
    assert has_element?(view, "[data-ui~='audit-list']", "Classroom teacher replaced")
    assert has_element?(view, "[data-ui~='audit-list']", "Alex Nguyen → Sophie Gagnon")
    refute has_element?(view, "[data-ui~='audit-list'] button")
    view |> element("#context-menu a[href='/admin/platform']") |> render_click()
    assert_patch(view, "/admin/platform")
    view |> element("#context-menu a[href='/admin/institution']") |> render_click()
    assert_patch(view, "/admin/institution")
    render_patch(view, "/admin/institution?section=classrooms")
    assert has_element?(view, "#admin-class-databases", "Sophie Gagnon")
  end

  test "teacher removal requires confirmation and protects assigned teachers", %{conn: conn} do
    {:ok, view, _} = live(conn, "/admin/institution")
    view |> element("#admin-teacher-alex button") |> render_click()
    view |> element("button[phx-click='confirm_remove']") |> render_click()
    assert has_element?(view, "button[phx-click='remove_member'][disabled]")
    render_click(view, "remove_member")
    assert has_element?(view, "[role='alert']", "Reassign")
    render_click(view, "close")
    view |> element("#admin-teacher-sophie button") |> render_click()
    view |> element("button[phx-click='confirm_remove']") |> render_click()
    render_click(view, "close")
    assert has_element?(view, "#admin-teacher-sophie")
    view |> element("#admin-teacher-sophie button") |> render_click()
    view |> element("button[phx-click='confirm_remove']") |> render_click()
    view |> element("button[phx-click='remove_member']") |> render_click()
    refute has_element?(view, "#admin-teacher-sophie")
    render_patch(view, "/admin/institution?section=history")
    assert has_element?(view, "[data-ui~='audit-list']", "Teacher removed from institution")
  end

  test "role editing, identity and invitation feedback work in the preview", %{conn: conn} do
    {:ok, view, _} = live(conn, "/admin/institution")
    view |> element("#admin-teacher-sophie button") |> render_click()
    view |> form("#member-form", member: %{role: "admin"}) |> render_submit()
    assert has_element?(view, "#admin-teacher-sophie", "Administrator")
    view |> form("#admin-search", query: "no-match") |> render_change()
    assert has_element?(view, "[data-ui~='empty']", "No matching teachers")
    view |> element("[data-ui~='toolbar'] button") |> render_click()
    assert has_element?(view, "#teacher-invitation-input[value^='https://gradepush.example/']")
    render_hook(view, "invitation_copied", %{"ok" => false})
    assert has_element?(view, "[role=status]", "manually")
    render_patch(view, "/admin/institution?section=settings")
    view |> form("#institution-form", institution: %{name: "  "}) |> render_submit()
    assert has_element?(view, "[role=alert]")
    view |> form("#institution-form", institution: %{name: "Mon cégep"}) |> render_submit()
    assert has_element?(view, "h1", "Mon cégep")
    assert has_element?(view, "#profile-menu", "Mon cégep")
  end

  test "platform status is explicitly simulated and separate from institution data", %{conn: conn} do
    {:ok, view, _} = live(conn, "/admin/platform?section=services&locale=fr")
    assert has_element?(view, "[data-ui~='admin-tag']", "État simulé")
    assert has_element?(view, "[data-ui~='service-list']", "PostgreSQL")
    refute has_element?(view, "[data-ui~='admin-table']")
    assert has_element?(view, "[data-ui~='language'][href*='section=services']")
    render_patch(view, "/admin/platform?section=unknown")
    assert has_element?(view, "[data-ui~='admin-properties']", "America/Toronto")
    refute has_element?(view, "input[type=password]")
  end
end
