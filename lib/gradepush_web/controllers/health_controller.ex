defmodule GradePushWeb.HealthController do
  use GradePushWeb, :controller

  alias Ecto.Adapters.SQL

  def show(conn, _params), do: json(conn, %{status: "ok"})

  def ready(conn, _params) do
    case SQL.query(GradePush.Repo, "SELECT 1", [], timeout: 1_000) do
      {:ok, _} -> json(conn, %{status: "ok"})
      {:error, _} -> conn |> put_status(:service_unavailable) |> json(%{status: "unavailable"})
    end
  rescue
    _ -> conn |> put_status(:service_unavailable) |> json(%{status: "unavailable"})
  catch
    :exit, _ -> conn |> put_status(:service_unavailable) |> json(%{status: "unavailable"})
  end
end
