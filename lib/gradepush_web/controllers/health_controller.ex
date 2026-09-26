defmodule GradePushWeb.HealthController do
  use GradePushWeb, :controller

  def show(conn, _params), do: json(conn, %{status: "ok"})
end
