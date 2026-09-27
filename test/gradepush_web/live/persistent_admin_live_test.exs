defmodule GradePushWeb.PersistentAdminLiveTest do
  use GradePushWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import GradePush.AccountsFixtures
  alias GradePush.Accounts

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
