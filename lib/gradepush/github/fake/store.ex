defmodule GradePush.GitHub.Fake.Store do
  @moduledoc false
  use GenServer

  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, %{}, Keyword.put_new(options, :name, __MODULE__))
  end

  def child_spec(options) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [options]},
      type: :worker
    }
  end

  def reset, do: GenServer.call(__MODULE__, :reset)
  def get(key, default \\ nil), do: GenServer.call(__MODULE__, {:get, key, default})
  def put(key, value), do: GenServer.call(__MODULE__, {:put, key, value})
  def put_new(key, value), do: GenServer.call(__MODULE__, {:put_new, key, value})

  def update(key, function) when is_function(function, 1),
    do: GenServer.call(__MODULE__, {:update, key, function})

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:reset, _from, _state), do: {:reply, :ok, %{}}

  def handle_call({:get, key, default}, _from, state),
    do: {:reply, Map.get(state, key, default), state}

  def handle_call({:put, key, value}, _from, state),
    do: {:reply, :ok, Map.put(state, key, value)}

  def handle_call({:put_new, key, value}, _from, state) do
    if Map.has_key?(state, key) do
      {:reply, :error, state}
    else
      {:reply, :ok, Map.put(state, key, value)}
    end
  end

  def handle_call({:update, key, function}, _from, state) do
    updated = function.(Map.get(state, key))
    {:reply, updated, Map.put(state, key, updated)}
  end
end
