defmodule GradePushWeb.PlatformWorkspace do
  @moduledoc false
  use Gettext, backend: GradePushWeb.Gettext

  alias GradePush.{Accounts, Operations, Time}
  alias GradePushWeb.{AdminWorkspace, Endpoint}

  def load(actor) do
    with {:ok, snapshot} <- Operations.snapshot(actor),
         {:ok, history} <- Accounts.list_audit(actor, :platform) do
      app = snapshot.github_app
      failed = Map.get(snapshot.jobs, "discarded", 0)

      queued =
        Enum.reduce(~w(available scheduled retryable), 0, &(&2 + Map.get(snapshot.jobs, &1, 0)))

      %{
        public_address: Endpoint.url(),
        timezone: Time.timezone(),
        github_app: if(app, do: app.slug, else: gettext("Not configured")),
        webhook_address: Endpoint.url() <> "/webhooks/github",
        database_status: gettext("Connected"),
        app_status:
          if(app, do: gettext("Credentials configured"), else: gettext("Not configured")),
        jobs_status:
          gettext("%{queued} queued · %{failed} failed", queued: queued, failed: failed),
        webhook_status: webhook_status(snapshot.last_webhook_at),
        history: Enum.map(history, &AdminWorkspace.event/1),
        preview?: false
      }
    else
      {:error, _} -> nil
    end
  end

  defp webhook_status(nil), do: gettext("No webhook received yet")

  defp webhook_status(datetime),
    do: gettext("Last delivery: %{time}", time: Time.format_datetime(datetime))
end
