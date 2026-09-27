defmodule GradePushWeb.Plugs.CacheBodyReader do
  @moduledoc false

  import Plug.Conn

  @max_body_size 2_000_000
  @webhook_path "/webhooks/github"

  def read_body(conn, options) do
    limit = min(Keyword.get(options, :length, @max_body_size), @max_body_size)
    read_chunks(conn, options, limit, [], 0)
  end

  defp read_chunks(conn, options, limit, chunks, size) do
    remaining = limit - size

    case Plug.Conn.read_body(conn, Keyword.put(options, :length, remaining)) do
      {:ok, chunk, conn} ->
        body = chunks |> Enum.reverse([chunk]) |> IO.iodata_to_binary()

        conn =
          if conn.request_path == @webhook_path, do: assign(conn, :raw_body, body), else: conn

        {:ok, body, conn}

      {:more, chunk, conn} when size + byte_size(chunk) < limit ->
        read_chunks(conn, options, limit, [chunk | chunks], size + byte_size(chunk))

      {:more, chunk, conn} ->
        {:more, chunks |> Enum.reverse([chunk]) |> IO.iodata_to_binary(), conn}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
