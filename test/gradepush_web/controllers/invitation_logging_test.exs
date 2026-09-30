defmodule GradePushWeb.InvitationLoggingTest do
  use GradePushWeb.ConnCase, async: true, group: :institution

  import ExUnit.CaptureLog

  test "invitation bearer tokens do not appear in request logs", %{conn: conn} do
    token = "invitation-secret-not-for-logs"

    logs =
      capture_log([level: :debug], fn ->
        conn = conn |> init_test_session(%{ui_preview: false}) |> get("/join/classroom/#{token}")
        assert redirected_to(conn) == "/auth/sign-in"
      end)

    refute logs =~ token
  end
end
