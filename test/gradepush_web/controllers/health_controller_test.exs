defmodule GradePushWeb.HealthControllerTest do
  use GradePushWeb.ConnCase

  test "liveness responds without a browser session", %{conn: conn} do
    conn = get(conn, ~p"/health")
    assert json_response(conn, 200) == %{"status" => "ok"}
    assert conn.resp_cookies == %{}
  end
end
