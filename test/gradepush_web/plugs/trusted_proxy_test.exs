defmodule GradePushWeb.Plugs.TrustedProxyTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Plug.Test
  alias GradePushWeb.Plugs.TrustedProxy

  test "only a configured peer may supply the client address" do
    request =
      %{conn(:get, "/") | remote_ip: {192, 0, 2, 1}}
      |> put_req_header("x-forwarded-for", "198.51.100.8")

    assert TrustedProxy.call(request, proxies: []).remote_ip == {192, 0, 2, 1}
    trusted = TrustedProxy.call(request, proxies: ["192.0.2.1"])
    assert trusted.remote_ip == {198, 51, 100, 8}
    assert trusted.private.trusted_proxy
  end

  test "chains stop at the closest untrusted address and malformed headers fail closed" do
    request = %{conn(:get, "/") | remote_ip: {192, 0, 2, 1}}
    options = [proxies: ["192.0.2.1", "2001:db8::1"]]
    chain = put_req_header(request, "x-forwarded-for", "203.0.113.99, 198.51.100.8, 2001:db8::1")
    assert TrustedProxy.call(chain, options).remote_ip == {198, 51, 100, 8}

    for header <- ["garbage", "198.51.100.8:443", "", String.duplicate("a", 1_025)] do
      assert request
             |> put_req_header("x-forwarded-for", header)
             |> TrustedProxy.call(options)
             |> Map.fetch!(:remote_ip) == request.remote_ip
    end
  end

  test "proxy DNS names are resolved while unresolvable names grant no trust" do
    request =
      %{conn(:get, "/") | remote_ip: {127, 0, 0, 1}}
      |> put_req_header("x-forwarded-for", "2001:db8::5")

    assert TrustedProxy.call(request, proxies: ["localhost"]).remote_ip ==
             {8193, 3512, 0, 0, 0, 0, 0, 5}

    assert TrustedProxy.call(request, proxies: ["unresolvable.invalid"]).remote_ip ==
             {127, 0, 0, 1}
  end

  test "explicit IPv4 and IPv6 networks honor their boundaries and reject malformed ranges" do
    for {peer, range, expected} <- [
          {{172, 16, 255, 255}, "172.16.0.0/16", true},
          {{172, 17, 0, 0}, "172.16.0.0/16", false},
          {{8193, 3512, 1, 0, 0, 0, 0, 1}, "2001:db8::/32", true},
          {{8193, 3513, 0, 0, 0, 0, 0, 1}, "2001:db8::/32", false},
          {{172, 16, 0, 1}, "172.16.0.0/33", false},
          {{172, 16, 0, 1}, "172.16.0.0/-1", false},
          {{127, 0, 0, 1}, "localhost/8", false}
        ] do
      result = TrustedProxy.call(%{conn(:get, "/") | remote_ip: peer}, proxies: [range])
      assert !!result.private[:trusted_proxy] == expected
    end
  end

  test "Fly client address requires a trusted peer and one valid IP, ignoring forged chains" do
    request =
      %{conn(:get, "/") | remote_ip: {172, 16, 30, 154}}
      |> put_req_header("fly-client-ip", "198.51.100.8")
      |> put_req_header("x-forwarded-for", "203.0.113.99, 66.241.125.140")

    options = [proxies: ["172.16.0.0/16"], client_ip_header: "fly-client-ip"]
    assert TrustedProxy.call(request, options).remote_ip == {198, 51, 100, 8}
    external = %{request | remote_ip: {203, 0, 113, 1}}
    assert TrustedProxy.call(external, options).remote_ip == external.remote_ip

    for header <- ["garbage", "198.51.100.8, 203.0.113.99", ""] do
      assert request
             |> put_req_header("fly-client-ip", header)
             |> TrustedProxy.call(options)
             |> Map.fetch!(:remote_ip) == request.remote_ip
    end
  end
end
