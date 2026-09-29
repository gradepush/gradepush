defmodule GradePushWeb.MetadataTest do
  use GradePushWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    original = Application.get_env(:gradepush, :demo_mode, false)
    Application.put_env(:gradepush, :demo_mode, false)
    on_exit(fn -> Application.put_env(:gradepush, :demo_mode, original) end)
    :ok
  end

  test "institution pages have branded titles and generic, non-indexable previews", %{conn: conn} do
    for path <- ["/auth/sign-in", "/setup", "/classrooms"] do
      response = get(conn, path)
      html = html_response(response, 200)
      assert get_resp_header(response, "x-robots-tag") == ["noindex"]
      assert attr(html, "meta[name=robots]", "content") == ["noindex"]
      assert text(html, "title") =~ " | GradePush"
      assert attr(html, "meta[property='og:title']", "content") == ["GradePush"]
      assert attr(html, "meta[name='twitter:card']", "content") == ["summary_large_image"]
      assert attr(html, "link[rel=canonical]", "href") == []
      assert attr(html, "meta[property='og:url']", "content") == []
    end
  end

  test "the public demo has server-rendered bilingual sharing metadata and clean canonical URLs",
       %{
         conn: conn
       } do
    enable_demo()
    origin = GradePushWeb.Endpoint.url()

    for {locale, title, description, og_locale} <- [
          {"en", "GitHub Classroom alternative", "open-source, self-hosted", "en_CA"},
          {"fr", "Alternative à GitHub Classroom", "libre et autohébergée", "fr_CA"}
        ] do
      response = get(conn, "/demo?locale=#{locale}&utm_source=share&token=private")
      html = html_response(response, 200)
      canonical = origin <> "/demo?locale=#{locale}"

      assert get_resp_header(response, "x-robots-tag") == ["index, follow"]
      assert attr(html, "meta[name=robots]", "content") == ["index, follow"]
      assert text(html, "title") == title <> " | GradePush"
      assert attr(html, "meta[property='og:title']", "content") == [title <> " | GradePush"]
      assert attr(html, "meta[property='og:locale']", "content") == [og_locale]
      assert [content] = attr(html, "meta[name=description]", "content")
      assert content =~ description
      assert text(html, "main") =~ content
      assert attr(html, "meta[property='og:description']", "content") == [content]
      assert attr(html, "meta[name='twitter:description']", "content") == [content]
      assert attr(html, "link[rel=canonical]", "href") == [canonical]
      assert attr(html, "meta[property='og:url']", "content") == [canonical]
      assert attr(html, "link[hreflang=en]", "href") == [origin <> "/demo?locale=en"]
      assert attr(html, "link[hreflang=fr]", "href") == [origin <> "/demo?locale=fr"]
      assert attr(html, "link[hreflang=x-default]", "href") == [origin <> "/demo?locale=en"]

      assert attr(html, "meta[property='og:image']", "content") ==
               [origin <> "/images/og-image.png"]
    end
  end

  test "sharing URLs use the configured endpoint instead of an untrusted request host", %{
    conn: conn
  } do
    enable_demo()
    html = %{conn | host: "attacker.example"} |> get("/demo?locale=en") |> html_response(200)

    assert attr(html, "link[rel=canonical]", "href") == [
             GradePushWeb.Endpoint.url() <> "/demo?locale=en"
           ]
  end

  test "demo workspaces, API responses and blocked routes stay out of search", %{conn: conn} do
    enable_demo()

    for path <- ["/classrooms", "/student/classrooms", "/health", "/setup"] do
      response = get(conn, path)
      assert get_resp_header(response, "x-robots-tag") == ["noindex"]
    end
  end

  test "a disabled demo does not advertise indexing", %{conn: conn} do
    response = get(conn, "/demo")
    assert redirected_to(response) == "/auth/sign-in"
    assert get_resp_header(response, "x-robots-tag") == ["noindex"]
  end

  test "an uninitialized demo redirect stays out of search", %{conn: conn} do
    Application.put_env(:gradepush, :demo_mode, true)
    response = get(conn, "/demo")
    assert redirected_to(response) == "/auth/sign-in"
    assert get_resp_header(response, "x-robots-tag") == ["noindex"]
  end

  test "language selection persists in public metadata", %{conn: conn} do
    enable_demo()
    response = conn |> init_test_session(locale: "fr") |> get("/demo?locale=unsupported")
    html = html_response(response, 200)
    assert text(html, "title") == "Alternative à GitHub Classroom | GradePush"

    assert attr(html, "link[rel=canonical]", "href") == [
             GradePushWeb.Endpoint.url() <> "/demo?locale=fr"
           ]
  end

  test "LiveView supplies updated titles with a stable browser suffix", %{conn: conn} do
    {:ok, view, html} = live(conn, "/classrooms")
    assert attr(html, "title", "data-suffix") == [" | GradePush"]
    assert page_title(view) == "My classrooms | GradePush"
    render_patch(view, "/teacher/settings")
    assert page_title(view) == "Settings"
  end

  test "the supplied sharing image is publicly served as a 1200 by 630 PNG", %{conn: conn} do
    response = get(conn, "/images/og-image.png")
    assert response.status == 200
    assert get_resp_header(response, "content-type") == ["image/png"]

    assert <<137, "PNG\r\n", 26, "\n", 13::32, "IHDR", 1200::32, 630::32, _::binary>> =
             response.resp_body
  end

  defp enable_demo do
    Application.put_env(:gradepush, :demo_mode, true)
    GradePush.Repo.insert!(%GradePush.Demo.InstanceMode{id: 1, mode: :demo})
  end

  defp attr(html, selector, name),
    do: html |> LazyHTML.from_document() |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

  defp text(html, selector),
    do: html |> LazyHTML.from_document() |> LazyHTML.query(selector) |> LazyHTML.text()
end
