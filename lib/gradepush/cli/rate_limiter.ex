defmodule GradePush.CLI.RateLimiter do
  @moduledoc false
  use GenServer

  @name __MODULE__

  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, options, name: @name)
  end

  def allow?(key, limit, window_seconds)
      when is_integer(limit) and limit > 0 and is_integer(window_seconds) and window_seconds > 0 do
    GenServer.call(@name, {:allow, key, limit, window_seconds * 1_000})
  end

  @impl true
  def init(_options), do: {:ok, %{windows: %{}, calls: 0}}

  @impl true
  def handle_call({:allow, key, limit, window_ms}, _from, state) do
    now = System.monotonic_time(:millisecond)
    active = state.windows |> Map.get(key, []) |> Enum.filter(&(now - &1 < window_ms))

    if length(active) < limit do
      windows = Map.put(state.windows, key, [now | active])
      calls = state.calls + 1
      windows = if rem(calls, 64) == 0, do: prune(windows, now, window_ms), else: windows
      {:reply, :ok, %{state | windows: windows, calls: calls}}
    else
      retry_after_ms = window_ms - (now - List.last(active))
      {:reply, {:error, max(retry_after_ms, 1)}, %{state | calls: state.calls + 1}}
    end
  end

  defp prune(windows, now, window_ms) do
    Map.reject(windows, fn {_key, timestamps} ->
      Enum.all?(timestamps, &(now - &1 >= window_ms))
    end)
  end
end
