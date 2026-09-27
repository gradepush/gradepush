defmodule GradePushWeb.DemoBoundaryTest do
  use ExUnit.Case, async: false

  import Plug.Test
  alias GradePush.GitHub
  alias GradePushWeb.Plugs.DemoBoundary

  setup do
    previous = Application.get_env(:gradepush, :demo_mode)
    Application.put_env(:gradepush, :demo_mode, true)
    on_exit(fn -> Application.put_env(:gradepush, :demo_mode, previous) end)
  end

  test "demo blocks GitHub authentication, setup, invitations and incoming webhooks" do
    for path <- ["/auth/github", "/auth/sign-in", "/setup", "/join/assignment/secret"] do
      conn = conn(:get, path) |> DemoBoundary.call([])
      assert conn.halted
      assert conn.status == 302
      assert Plug.Conn.get_resp_header(conn, "location") == ["/demo"]
    end

    conn = conn(:post, "/webhooks/github", "untrusted") |> DemoBoundary.call([])
    assert conn.status == 403
    assert conn.halted
    refute conn(:delete, "/auth/logout") |> DemoBoundary.call([]) |> Map.fetch!(:halted)
    assert GitHub.adapter() == GitHub.Fake
  end

  test "normal installations keep their authentication and webhook routes" do
    Application.put_env(:gradepush, :demo_mode, false)
    refute conn(:get, "/setup") |> DemoBoundary.call([]) |> Map.fetch!(:halted)
    refute conn(:post, "/webhooks/github") |> DemoBoundary.call([]) |> Map.fetch!(:halted)
  end
end
