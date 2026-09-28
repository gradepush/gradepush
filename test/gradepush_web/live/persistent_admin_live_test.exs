defmodule GradePushWeb.PersistentAdminLiveTest do
  use GradePushWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import GradePush.AccountsFixtures
  alias GradePush.Accounts

  test "student removal requires confirmation, refreshes the directory and is audited", %{
    conn: conn
  } do
    %{user: admin} = bootstrap_fixture()
    student = GradePush.TeachingFixtures.student_fixture(%{student_name: "Camille Martin"})

    {:ok, view, _} =
      conn |> log_in_user(admin) |> live("/admin/institution?section=students&locale=fr")

    row = "#institution-student-#{student.id}"
    view |> element("#{row} button", "Retirer") |> render_click()
    assert has_element?(view, "#admin-dialog", "Camille Martin")
    assert Accounts.student?(student)
    view |> element("#cancel-student-removal") |> render_click()
    assert Accounts.student?(student)
    refute has_element?(view, "#admin-dialog")
    view |> element("#{row} button", "Retirer") |> render_click()
    view |> element("#admin-dialog button", "Retirer") |> render_click()
    refute Accounts.student?(student)
    refute has_element?(view, row)
    assert has_element?(view, "[data-ui=empty]")
    render_patch(view, "/admin/institution?section=history&locale=fr")
    assert has_element?(view, "[data-ui=audit-list]", "Étudiant retiré de l’établissement")
  end

  test "student removal rechecks administrator permission at confirmation", %{conn: conn} do
    %{user: admin} = bootstrap_fixture()
    successor = user_fixture()
    teacher_membership_fixture(successor)
    {:ok, _} = Accounts.change_role(admin, successor.id, :admin)
    student = GradePush.TeachingFixtures.student_fixture()
    {:ok, view, _} = conn |> log_in_user(admin) |> live("/admin/institution?section=students")
    view |> element("#institution-student-#{student.id} button", "Remove") |> render_click()
    {:ok, _} = Accounts.change_role(successor, admin.id, :teacher)
    view |> element("#admin-dialog button", "Remove") |> render_click()
    assert Accounts.student?(student)
    assert has_element?(view, "[role=alert]", "You no longer have permission")
  end

  test "teachers can be removed through a confirmation dialog", %{conn: conn} do
    %{user: admin} = bootstrap_fixture()
    teacher = user_fixture(%{name: "Departing Teacher"})
    teacher_membership_fixture(teacher)
    {:ok, view, _} = conn |> log_in_user(admin) |> live("/admin/institution?section=teachers")
    view |> element("button[aria-label='Manage Departing Teacher']") |> render_click()
    view |> element("button", "Remove from institution") |> render_click()
    assert Accounts.teacher?(teacher)
    view |> element("#admin-dialog button", "Remove") |> render_click()
    refute Accounts.teacher?(teacher)
    assert Accounts.get_user(teacher.id)
  end

  test "institution student directory supports search, pagination and empty states", %{conn: conn} do
    %{user: admin} = bootstrap_fixture()
    {:ok, view, _} = conn |> log_in_user(admin) |> live("/admin/institution?section=students")
    assert has_element?(view, "[data-ui=empty]", "No registered students yet")

    for n <- 1..26 do
      suffix = n |> to_string() |> String.pad_leading(2, "0")

      GradePush.TeachingFixtures.student_fixture(%{
        student_name: "Student #{suffix}",
        student_id: "ID-#{suffix}",
        login: "student-#{suffix}"
      })
    end

    render_patch(view, "/admin/institution?section=students")
    assert has_element?(view, "a[href='https://github.com/student-01']")
    refute has_element?(view, "a[href='https://github.com/student-26']")
    view |> element("button", "Next") |> render_click()
    assert has_element?(view, "a[href='https://github.com/student-26']")
    assert has_element?(view, "button[disabled]", "Next")
    view |> form("#student-directory-search", query: "ID-01") |> render_change()
    assert has_element?(view, "a[href='https://github.com/student-01']")
    refute has_element?(view, "nav[aria-label='Student pages']")
    view |> form("#student-directory-search", query: "missing") |> render_change()
    assert has_element?(view, "[data-ui=empty]", "No matching students")
    refute has_element?(view, "a[href^='/classrooms/']")
  end

  test "platform access transfer requires confirmation and keeps institution roles", %{conn: conn} do
    %{user: owner} = bootstrap_fixture()
    successor = user_fixture(%{login: "next-operator", name: "Next Operator"})
    {:ok, view, _} = conn |> log_in_user(owner) |> live("/admin/platform?section=administrators")
    assert has_element?(view, "#platform-admin-#{owner.id} button[disabled]")

    view |> element("button", "Add an administrator") |> render_click()
    view |> form("#platform-admin-form", operator: %{login: "missing"}) |> render_submit()
    assert has_element?(view, "[role=alert]", "Account not found")
    view |> form("#platform-admin-form", operator: %{login: successor.login}) |> render_submit()
    refute Accounts.operator?(successor)
    assert has_element?(view, "#admin-dialog", "@next-operator")
    view |> element("button", "Grant platform access") |> render_click()
    assert Accounts.operator?(successor)
    refute Accounts.admin?(successor)
    assert has_element?(view, "#platform-admin-#{successor.id}")
    render_patch(view, "/admin/platform?section=history")
    assert has_element?(view, "[data-ui=audit-list]", "Platform administrator added")
    render_patch(view, "/admin/platform?section=administrators")

    view |> element("#platform-admin-#{owner.id} button", "Remove access") |> render_click()
    assert Accounts.operator?(owner)
    view |> element("#admin-dialog button", "Cancel") |> render_click()
    assert Accounts.operator?(owner)
    view |> element("#platform-admin-#{owner.id} button", "Remove access") |> render_click()
    view |> element("#admin-dialog button", "Remove access") |> render_click()
    assert_redirect(view, "/")
    refute Accounts.operator?(owner)
    assert Accounts.admin?(owner)

    successor_conn = log_in_user(conn, successor)
    {:ok, next_view, _} = live(successor_conn, "/admin/platform?section=administrators")
    assert has_element?(next_view, "#platform-admin-#{successor.id} button[disabled]")
    assert {:error, {:redirect, %{to: "/"}}} = live(successor_conn, "/admin/institution")
  end

  test "an open platform page cannot grant access after its operator is revoked", %{conn: conn} do
    %{user: owner} = bootstrap_fixture()
    successor = user_fixture()
    target = user_fixture()
    {:ok, _} = Accounts.grant_platform_operator(owner, successor.id)
    {:ok, view, _} = conn |> log_in_user(owner) |> live("/admin/platform?section=administrators")
    view |> element("button", "Add an administrator") |> render_click()
    view |> form("#platform-admin-form", operator: %{login: target.login}) |> render_submit()
    {:ok, _} = Accounts.remove_platform_operator(successor, owner.id)
    view |> element("button", "Grant platform access") |> render_click()
    refute Accounts.operator?(target)
    assert has_element?(view, "[role=alert]", "You no longer have permission")
  end

  test "footer links persist, appear before sign-in, and disappear when cleared", %{conn: conn} do
    %{user: admin} = bootstrap_fixture()
    {:ok, view, _} = conn |> log_in_user(admin) |> live("/admin/institution?section=settings")
    assert has_element?(view, "footer a[href='https://github.com/gradepush']", "GitHub")
    refute has_element?(view, "footer a", "Privacy")

    view |> form("#footer-form", footer: %{privacy_url: "javascript:alert(1)"}) |> render_submit()
    assert has_element?(view, "#footer_privacy_url[aria-invalid='true']")
    assert_push_event(view, "focus-invalid", %{id: "footer-form"})
    refute has_element?(view, "footer a[href^='javascript:']")

    view
    |> form("#footer-form",
      footer: %{
        privacy_url: "https://example.org/privacy",
        support_url: "mailto:help@example.org"
      }
    )
    |> render_submit()

    assert has_element?(view, "footer a[href='https://example.org/privacy']", "Privacy")
    assert has_element?(view, "footer a[href='mailto:help@example.org']", "Assistance")

    {:ok, public, _} = live(conn, "/auth/sign-in?locale=fr")
    assert has_element?(public, "footer a[href='https://example.org/privacy']", "Confidentialité")

    view |> form("#footer-form", footer: %{privacy_url: ""}) |> render_submit()
    refute has_element?(view, "footer a", "Privacy")
    assert has_element?(view, "footer a[href='mailto:help@example.org']")
    assert is_nil(Accounts.footer_links().privacy_url)
    render_patch(view, "/admin/institution?section=history")
    assert has_element?(view, "[data-ui~='audit-list']", "Institution links updated")
  end

  test "institution changes persist and create an audit entry", %{conn: conn} do
    %{user: admin} = bootstrap_fixture()
    conn = log_in_user(conn, admin)
    {:ok, view, html} = live(conn, "/admin/institution?section=settings")
    refute html =~ "institution-demo"

    view
    |> form("#institution-form", institution: %{name: "Collège des tests"})
    |> render_submit()

    assert Accounts.institution().name == "Collège des tests"
    {:ok, _, refreshed} = live(conn, "/admin/institution?section=history")
    assert refreshed =~ "Collège des tests"
    assert refreshed =~ admin.login
  end

  test "ordinary teachers cannot open administrative or operator screens", %{conn: conn} do
    bootstrap_fixture()
    teacher = user_fixture()
    teacher_membership_fixture(teacher)
    conn = log_in_user(conn, teacher)

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/institution")
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/platform")
  end

  test "platform diagnostics show actual local state rather than sample availability", %{
    conn: conn
  } do
    %{user: admin} = bootstrap_fixture()
    {:ok, _, html} = conn |> log_in_user(admin) |> live("/admin/platform?section=services")
    assert html =~ "queued"
    assert html =~ "Not configured"
    refute html =~ "Simulated status"
    refute html =~ "Last event received 2 minutes ago"
  end
end
