defmodule GradePushWeb.LocaleTest do
  use GradePushWeb.ConnCase

  test "the classroom workspace defaults to English", %{conn: conn} do
    body = conn |> get(~p"/classrooms") |> html_response(200)
    assert body =~ ~s(lang="en")
    assert body =~ "My classrooms"
    assert body =~ "Programming I"
  end

  test "French selection persists across requests", %{conn: conn} do
    conn = get(conn, ~p"/classrooms?locale=fr")
    body = html_response(conn, 200)
    assert body =~ "Programmation I"
    refute body =~ "Automne 2026"
    assert get_session(conn, :locale) == "fr"

    body = conn |> recycle() |> get(~p"/classrooms") |> html_response(200)
    assert body =~ ~s(lang="fr")
    assert body =~ "Programmation I"
  end

  test "unsupported and malformed locales preserve a valid saved language", %{conn: conn} do
    for locale <- ["de", ["fr"], %{"value" => "fr"}] do
      conn = conn |> init_test_session(locale: "fr") |> get("/classrooms", %{locale: locale})
      assert html_response(conn, 200) =~ "Programmation I"
      assert get_session(conn, :locale) == "fr"
    end
  end

  test "a corrupt locale session falls back to English", %{conn: conn} do
    conn = conn |> init_test_session(locale: "invalid") |> get(~p"/classrooms")
    assert html_response(conn, 200) =~ "Programming I"
    assert get_session(conn, :locale) == "en"
  end
end
