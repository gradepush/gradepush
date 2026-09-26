defmodule GradePush.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        GradePushWeb.Telemetry,
        GradePush.Repo,
        {Phoenix.PubSub, name: GradePush.PubSub},
        {Oban, Application.fetch_env!(:gradepush, Oban)}
      ] ++ endpoint_children()

    Supervisor.start_link(children, strategy: :one_for_one, name: GradePush.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    if Application.get_env(:gradepush, :start_endpoint, true) do
      GradePushWeb.Endpoint.config_change(changed, removed)
    end

    :ok
  end

  defp endpoint_children do
    if Application.get_env(:gradepush, :start_endpoint, true),
      do: [GradePushWeb.Endpoint],
      else: []
  end
end
