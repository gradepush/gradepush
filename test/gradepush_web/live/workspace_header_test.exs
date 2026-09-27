defmodule GradePushWeb.WorkspaceHeaderTest do
  use GradePushWeb.ConnCase

  import Phoenix.LiveViewTest

  test "teacher navigation opens settings and the connection preview", %{conn: conn} do
    {:ok, view, _} = live(conn, "/classrooms/programming?locale=fr")
    assert has_element?(view, ".cp-navigation a[aria-current='page']", "Classes")
    assert has_element?(view, "#profile-menu", "Cégep de Sorel-Tracy")
    refute has_element?(view, ".cp-institution")
    assert has_element?(view, ".cp-profile-identity .cp-avatar", "JR")

    view |> element(".cp-navigation a[href='/teacher/settings']") |> render_click()
    assert_patch(view, "/teacher/settings")
    assert has_element?(view, "h1", "Paramètres")
    assert has_element?(view, ".cp-navigation a[aria-current='page']", "Paramètres")
    assert has_element?(view, "#github-account-title", "Compte GitHub")
    refute has_element?(view, ".cp-organization-row")

    view
    |> element(".cp-settings-nav a[href='/teacher/settings?section=organizations']")
    |> render_click()

    assert_patch(view, "/teacher/settings?section=organizations")
    assert has_element?(view, ".cp-settings-nav a[aria-current='page']", "Organisations")
    refute has_element?(view, "#github-account-title")
    assert has_element?(view, ".cp-organization-row", "cegep-sorel-tracy")
    view |> element(".cp-settings-actions button") |> render_click()
    assert has_element?(view, "[role='dialog']", "Aucune permission ne sera modifiée")
    assert has_element?(view, "[role='dialog'] button[disabled]", "Continuer sur GitHub")
    render_click(view, "close")
    refute has_element?(view, "[role='dialog']")
    view |> element(".cp-navigation a[href='/classrooms']") |> render_click()
    assert has_element?(view, "h1", "Mes classes")
  end

  test "settings sections support direct links and language switching", %{conn: conn} do
    {:ok, view, _} = live(conn, "/teacher/settings?section=organizations&locale=fr")
    assert has_element?(view, "#github-organizations-title")

    assert has_element?(
             view,
             ".cp-language[href*='section=organizations'][href*='locale=en']"
           )

    view |> element(".cp-settings-nav a[href='/teacher/settings']") |> render_click()
    assert has_element?(view, "#github-account-title")
    refute has_element?(view, "#github-organizations-title")
    render_patch(view, "/teacher/settings?section=unknown")
    assert has_element?(view, "#github-account-title")
  end

  test "the direct language switch retains the current assignment section", %{conn: conn} do
    for {locale, target} <- [{"fr", "en"}, {"en", "fr"}] do
      {:ok, view, _} =
        live(conn, "/classrooms/programming/assignments/cli?view=tests&locale=#{locale}")

      refute has_element?(view, "#language-menu")

      assert has_element?(
               view,
               ".cp-language[lang='#{target}'][href*='locale=#{target}'][href*='view=tests']",
               String.upcase(target)
             )

      assert has_element?(view, ".cp-language .hero-globe-alt")
    end
  end

  test "sign-out leads to the explicitly simulated sign-in screen", %{conn: conn} do
    {:ok, view, _} = live(conn, "/classrooms")
    view |> element("#profile-menu a[href='/signed-out']") |> render_click()
    assert_patch(view, "/signed-out")
    assert has_element?(view, "h1", "See you soon")
    assert has_element?(view, ".cp-sign-in", "simulated in this preview")
    refute has_element?(view, ".cp-navigation")
    refute has_element?(view, "#profile-menu")
    view |> element(".cp-sign-in a") |> render_click()
    assert_patch(view, "/classrooms")
    assert has_element?(view, ".cp-navigation")
    assert has_element?(view, "h1", "My classrooms")
  end
end
