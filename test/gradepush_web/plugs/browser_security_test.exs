defmodule GradePushWeb.Plugs.BrowserSecurityTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Plug.Test
  alias GradePushWeb.Plugs.BrowserSecurity

  test "scripts and connections are scoped while the GitHub setup form remains allowed" do
    conn = BrowserSecurity.call(conn(:get, "/setup"), [])
    [policy] = get_resp_header(conn, "content-security-policy")

    directives =
      Map.new(String.split(policy, "; "), fn directive ->
        [name, value] = String.split(directive, " ", parts: 2)
        {name, value}
      end)

    assert directives["script-src"] == "'self'"
    assert directives["object-src"] == "'none'"
    assert directives["base-uri"] == "'none'"
    assert directives["form-action"] == "'self' https://github.com"
    assert directives["connect-src"] =~ "'self'"
    refute directives["connect-src"] =~ "*"
    assert get_resp_header(conn, "referrer-policy") == ["strict-origin-when-cross-origin"]
  end
end
