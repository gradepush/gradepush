defmodule GradePushWeb.PageControllerTest do
  use GradePushWeb.ConnCase

  test "the baseline defaults to English", %{conn: conn} do
    body = conn |> get(~p"/") |> html_response(200)
    assert body =~ ~s(lang="en")
    assert body =~ "GradePush is taking shape"
  end

  test "French selection persists across requests", %{conn: conn} do
    conn = get(conn, ~p"/?locale=fr")
    assert html_response(conn, 200) =~ "GradePush prend forme"
    assert get_session(conn, :locale) == "fr"

    body = conn |> recycle() |> get(~p"/") |> html_response(200)
    assert body =~ ~s(lang="fr")
    assert body =~ "GradePush prend forme"
  end

  test "unsupported and malformed locales preserve a valid saved language", %{conn: conn} do
    for locale <- ["de", ["fr"], %{"value" => "fr"}] do
      conn = conn |> init_test_session(locale: "fr") |> get("/", %{locale: locale})
      assert html_response(conn, 200) =~ "GradePush prend forme"
      assert get_session(conn, :locale) == "fr"
    end
  end

  test "a corrupt locale session falls back to English", %{conn: conn} do
    conn = conn |> init_test_session(locale: "invalid") |> get(~p"/")
    assert html_response(conn, 200) =~ "GradePush is taking shape"
    assert get_session(conn, :locale) == "en"
  end
end
