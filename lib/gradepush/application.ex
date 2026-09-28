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
        GradePush.CLI.RateLimiter
      ] ++
        github_children() ++
        instance_children() ++
        [{Oban, Application.fetch_env!(:gradepush, Oban)}] ++
        setup_children() ++ endpoint_children()

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

  defp setup_children do
    if Application.get_env(:gradepush, :setup_token_server, true) and
         not GradePush.Demo.enabled?(),
       do: [GradePush.Installation.SetupTokenServer],
       else: []
  end

  defp instance_children do
    if Application.get_env(:gradepush, :initialize_instance, true),
      do: [GradePush.Demo.Boot],
      else: []
  end

  defp github_children do
    if GradePush.GitHub.adapter() == GradePush.GitHub.Fake,
      do: [GradePush.GitHub.Fake.Store],
      else: []
  end
end
