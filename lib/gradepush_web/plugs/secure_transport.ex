defmodule GradePushWeb.Plugs.SecureTransport do
  @moduledoc false
  @behaviour Plug

  def init(options), do: options

  def call(conn, options) do
    url = Keyword.get(options, :url, GradePushWeb.Endpoint.config(:url))

    if Keyword.get(url, :scheme, "http") == "https" do
      options =
        Plug.SSL.init(
          host: url[:host],
          rewrite_on: if(conn.private[:trusted_proxy], do: [:x_forwarded_proto], else: []),
          exclude: [paths: ["/health", "/health/ready"]]
        )

      Plug.SSL.call(conn, options)
    else
      conn
    end
  end
end
