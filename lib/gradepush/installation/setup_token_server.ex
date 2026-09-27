defmodule GradePush.Installation.SetupTokenServer do
  @moduledoc false
  use GenServer
  require Logger

  alias GradePush.Installation

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok) do
    send(self(), :initialize)
    {:ok, %{attempt: 0}}
  end

  @impl true
  def handle_info(:initialize, state) do
    case Installation.initialize_bootstrap() do
      {:ok, _status} ->
        {:noreply, %{state | attempt: 0}}

      {:error, reason} ->
        attempt = state.attempt + 1
        delay = min(1_000 * trunc(:math.pow(2, min(attempt, 5))), 30_000)
        Logger.error("GradePush setup credential initialization failed: #{inspect(reason)}")
        Process.send_after(self(), :initialize, delay)
        {:noreply, %{state | attempt: attempt}}
    end
  end
end
