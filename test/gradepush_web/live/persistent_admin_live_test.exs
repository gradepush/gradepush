defmodule GradePushWeb.PersistentAdminLiveTest do
  use GradePushWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import GradePush.AccountsFixtures
  alias GradePush.Accounts

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
