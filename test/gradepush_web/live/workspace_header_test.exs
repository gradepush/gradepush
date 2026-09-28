defmodule GradePushWeb.WorkspaceHeaderTest do
  use GradePushWeb.ConnCase

  import Phoenix.LiveViewTest

  test "the context selector lists only the workspaces supplied to the header" do
    assigns = %{
      user: %{name: "Teacher", handle: "teacher", initials: "TE"},
      institution: "College",
      action: :index,
      locale: "en",
      language_urls: %{"fr" => "/?locale=fr", "en" => "/?locale=en"}
    }

    html = render_component(&GradePushWeb.WorkspaceLayout.header/1, assigns)
    refute html =~ "context-menu"
    refute html =~ "/admin/"

    html =
      render_component(
        &GradePushWeb.WorkspaceLayout.header/1,
        Map.put(assigns, :contexts, [:teaching, :institution])
      )

    assert html =~ "/admin/institution"
    refute html =~ "/admin/platform"
  end

  test "teacher navigation opens settings and the connection preview", %{conn: conn} do
    {:ok, view, _} = live(conn, "/classrooms/programming?locale=fr")
    assert has_element?(view, "[data-ui~='navigation'] a[aria-current='page']", "Classes")
    assert has_element?(view, "#profile-menu", "Cégep de Sorel-Tracy")
    refute has_element?(view, "[data-ui~='institution']")
    assert has_element?(view, "[data-ui~='profile-identity'] [data-avatar]", "JR")

    view |> element("[data-ui~='navigation'] a[href='/teacher/settings']") |> render_click()
    assert_patch(view, "/teacher/settings")
    assert has_element?(view, "h1", "Paramètres")
    assert has_element?(view, "[data-ui~='navigation'] a[aria-current='page']", "Paramètres")
    assert has_element?(view, "#github-account-title", "Compte GitHub")
    refute has_element?(view, "[data-ui~='organization-row']")

    view
    |> element("[data-ui~='settings-nav'] a[href='/teacher/settings?section=organizations']")
    |> render_click()

    assert_patch(view, "/teacher/settings?section=organizations")
    assert has_element?(view, "[data-ui~='settings-nav'] a[aria-current='page']", "Organisations")
    refute has_element?(view, "#github-account-title")
    assert has_element?(view, "[data-ui~='organization-row']", "cegep-sorel-tracy")

    view
    |> element("[data-ui~='settings-actions'] button", "Déjà installée sur GitHub?")
    |> render_click()

    assert has_element?(view, "[role='dialog']", "Les connexions GitHub ne sont pas disponibles")
    refute has_element?(view, "[role='dialog'] a[href='/github/organizations/connect']")
    render_click(view, "close")
    refute has_element?(view, "[role='dialog']")
    view |> element("[data-ui~='navigation'] a[href='/classrooms']") |> render_click()
    assert has_element?(view, "h1", "Mes classes")
  end

  test "settings sections support direct links and language switching", %{conn: conn} do
    {:ok, view, _} = live(conn, "/teacher/settings?section=organizations&locale=fr")
    assert has_element?(view, "#github-organizations-title")

    assert has_element?(
             view,
             "[data-ui~='language'][href*='section=organizations'][href*='locale=en']"
           )

    view |> element("[data-ui~='settings-nav'] a[href='/teacher/settings']") |> render_click()
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
               "[data-ui~='language'][lang='#{target}'][href*='locale=#{target}'][href*='view=tests']",
               String.upcase(target)
             )

      assert has_element?(view, "[data-ui~='language'] .hero-globe-alt")
    end
  end

  test "sign-out leads to the explicitly simulated sign-in screen", %{conn: conn} do
    {:ok, view, _} = live(conn, "/classrooms")
    view |> element("#profile-menu a[href='/signed-out']") |> render_click()
    assert_patch(view, "/signed-out")
    assert has_element?(view, "h1", "See you soon")
    assert has_element?(view, "[data-ui~='sign-in']", "simulated in this preview")
    refute has_element?(view, "[data-ui~='navigation']")
    refute has_element?(view, "#profile-menu")
    view |> element("[data-ui~='sign-in'] a") |> render_click()
    assert_patch(view, "/classrooms")
    assert has_element?(view, "[data-ui~='navigation']")
    assert has_element?(view, "h1", "My classrooms")
  end
end
