defmodule GradePushWeb.Plugs.TrustedProxy do
  @moduledoc "Accepts forwarding headers only from explicitly configured proxy peers."
  @behaviour Plug
  import Plug.Conn

  def init(options), do: options

  def call(conn, options) do
    proxies =
      Keyword.get(options, :proxies, Application.get_env(:gradepush, :trusted_proxies, []))

    trusted = Enum.flat_map(proxies, &addresses/1)

    header =
      Keyword.get(
        options,
        :client_ip_header,
        Application.get_env(:gradepush, :trusted_proxy_client_ip_header, "x-forwarded-for")
      )

    if trusted?(conn.remote_ip, trusted) do
      conn
      |> put_private(:trusted_proxy, true)
      |> client_address(trusted, header)
    else
      conn
    end
  end

  defp client_address(conn, _trusted, "fly-client-ip") do
    with [header] when byte_size(header) <= 64 <- get_req_header(conn, "fly-client-ip"),
         {:ok, address} <- parse_address(header) do
      %{conn | remote_ip: address}
    else
      _ -> conn
    end
  end

  defp client_address(conn, trusted, "x-forwarded-for") do
    with [header] when byte_size(header) <= 1_024 <- get_req_header(conn, "x-forwarded-for"),
         entries when length(entries) in 1..20 <- String.split(header, ",", trim: true),
         parsed <- Enum.map(entries, &parse_address(String.trim(&1))),
         true <- Enum.all?(parsed, &match?({:ok, _}, &1)) do
      client =
        parsed
        |> Enum.reverse()
        |> Enum.find_value(&untrusted_address(&1, trusted))

      if client, do: %{conn | remote_ip: client}, else: conn
    else
      _ -> conn
    end
  end

  defp untrusted_address({:ok, address}, trusted),
    do: if(not trusted?(address, trusted), do: address)

  defp addresses(proxy) do
    case String.split(proxy, "/", parts: 2) do
      [host, prefix] -> network(host, prefix)
      [host] -> host_addresses(host)
    end
  end

  defp host_addresses(proxy) do
    case parse_address(proxy) do
      {:ok, address} -> [address]
      {:error, _} -> Enum.flat_map([:inet, :inet6], &resolve(proxy, &1))
    end
  end

  defp network(host, prefix) do
    with {:ok, address} <- parse_address(host),
         {bits, ""} <- Integer.parse(prefix),
         true <- bits in 0..bit_size(address_binary(address)) do
      [{:network, address, bits}]
    else
      _ -> []
    end
  end

  defp trusted?(address, trusted) do
    Enum.any?(trusted, fn
      {:network, network, bits} when tuple_size(address) == tuple_size(network) ->
        <<prefix::size(^bits), _::bitstring>> = address_binary(address)
        <<network_prefix::size(^bits), _::bitstring>> = address_binary(network)
        prefix == network_prefix

      trusted_address ->
        address == trusted_address
    end)
  end

  defp address_binary(address) do
    bits = if tuple_size(address) == 4, do: 8, else: 16
    for part <- Tuple.to_list(address), into: <<>>, do: <<part::size(bits)>>
  end

  defp resolve(proxy, family) do
    case :inet.getaddrs(String.to_charlist(proxy), family, 500) do
      {:ok, addresses} -> addresses
      {:error, _} -> []
    end
  end

  defp parse_address(value), do: :inet.parse_strict_address(String.to_charlist(value))
end
