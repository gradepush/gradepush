defmodule GradePush.Repo do
  use Ecto.Repo,
    otp_app: :gradepush,
    adapter: Ecto.Adapters.Postgres
end
