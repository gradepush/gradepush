defmodule GradePushWeb.Preview.Platform do
  @moduledoc "Example platform configuration and status without inspecting the host or external services."
  use Gettext, backend: GradePushWeb.Gettext

  def for_user(user) do
    %{
      public_address: "https://gradepush.example",
      timezone: "America/Toronto",
      github_app: "GradePush Sorel-Tracy",
      webhook_address: "https://gradepush.example/webhooks/github",
      database_status: gettext("Database connection available"),
      app_status: gettext("App credentials configured"),
      jobs_status: gettext("No failed jobs in this example"),
      webhook_status: gettext("Last event received 2 minutes ago"),
      history: [
        %{
          actor: user.name,
          action: gettext("GitHub App configured"),
          target: "GradePush Sorel-Tracy",
          time: "2026-09-22 09:15"
        },
        %{
          actor: user.name,
          action: gettext("Instance initialized"),
          target: "gradepush.example",
          time: "2026-09-22 09:10"
        }
      ]
    }
  end
end
