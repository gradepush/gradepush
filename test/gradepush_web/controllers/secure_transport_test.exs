defmodule GradePushWeb.SecureTransportTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Plug.Test
  alias GradePushWeb.Plugs.SecureTransport

  @https [url: [scheme: "https", host: "grades.example"]]

  test "public HTTP redirects to the configured host, never an attacker-supplied Host" do
    conn = conn(:get, "http://attacker.example/classrooms") |> SecureTransport.call(@https)
    assert conn.halted
    assert get_resp_header(conn, "location") == ["https://grades.example/classrooms"]
  end

  test "HTTPS from the TLS proxy results in secure cookies and HSTS" do
    conn =
      conn(:get, "/classrooms")
      |> put_req_header("x-forwarded-proto", "https")
      |> put_private(:trusted_proxy, true)
      |> SecureTransport.call(@https)
      |> put_resp_cookie("test", "value")

    refute conn.halted
    assert conn.scheme == :https
    assert conn.resp_cookies["test"].secure
    assert get_resp_header(conn, "strict-transport-security") != []
  end

  test "an untrusted client cannot suppress the HTTPS redirect with forwarding headers" do
    conn =
      conn(:get, "/classrooms")
      |> put_req_header("x-forwarded-proto", "https")
      |> SecureTransport.call(@https)

    assert conn.halted
    assert conn.scheme == :http
  end

  test "local HTTP development and container health checks remain reachable" do
    refute conn(:get, "/health") |> SecureTransport.call(@https) |> Map.get(:halted)

    refute conn(:get, "/setup")
           |> SecureTransport.call(url: [scheme: "http", host: "localhost"])
           |> Map.get(:halted)
  end
end
