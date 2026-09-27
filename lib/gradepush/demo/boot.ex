defmodule GradePush.Demo.Boot do
  @moduledoc false

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [[]]},
      restart: :temporary
    }
  end

  def start_link(_opts) do
    case GradePush.Demo.initialize() do
      :ok -> :ignore
      {:error, reason} -> {:error, {:unsafe_instance_mode, reason}}
    end
  end
end
