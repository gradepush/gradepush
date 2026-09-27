defmodule GradePushWeb.Plugs.CacheBodyReaderTest do
  use ExUnit.Case, async: true

  alias GradePushWeb.Plugs.CacheBodyReader

  test "caches the exact raw webhook body only on the webhook route" do
    body = ~s({"action":"push","after":"abc"})

    conn = Plug.Test.conn(:post, "/webhooks/github", body)
    assert {:ok, ^body, %{assigns: %{raw_body: ^body}}} = CacheBodyReader.read_body(conn, [])

    other_conn = Plug.Test.conn(:post, "/sign-in", body)
    assert {:ok, ^body, %{assigns: assigns}} = CacheBodyReader.read_body(other_conn, [])
    refute Map.has_key?(assigns, :raw_body)
  end

  test "returns an oversized marker before any oversized body reaches JSON parsing" do
    body = :binary.copy("a", 2_000_001)
    conn = Plug.Test.conn(:post, "/webhooks/github", body)

    assert {:more, partial, _conn} = CacheBodyReader.read_body(conn, [])
    assert byte_size(partial) <= 2_000_000
  end
end
