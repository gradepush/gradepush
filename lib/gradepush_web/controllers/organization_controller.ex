defmodule GradePushWeb.OrganizationController do
  use GradePushWeb, :controller

  alias GradePush.{Accounts, Classrooms, Demo, Installation}
  alias GradePushWeb.AccountComponents

  @settings "/teacher/settings?section=organizations"

  def new(conn, _params) do
    with true <- allowed?(conn),
         %{slug: slug} when is_binary(slug) and slug != "" <- Installation.github_app_metadata() do
      state = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

      conn
      |> put_session(:organization_connection, %{
        "state" => state,
        "user_id" => conn.assigns.current_user.id,
        "issued_at" => System.system_time(:second)
      })
      |> redirect(
        external:
          "https://github.com/apps/#{URI.encode(slug)}/installations/new?#{URI.encode_query(%{state: state})}"
      )
    else
      _ -> failure(conn, :unauthorized)
    end
  end

  def callback(conn, params) do
    pending = get_session(conn, :organization_connection)
    conn = delete_session(conn, :organization_connection)

    if allowed?(conn) and valid_state?(pending, params["state"], conn.assigns.current_user.id) do
      connect(conn, params)
    else
      failure(conn, :invalid_state)
    end
  end

  defp connect(conn, %{"setup_action" => "request"}) do
    conn
    |> put_flash(
      :info,
      gettext(
        "An organization owner must approve the GitHub App installation. Once approved, connect it using ‘Already installed on GitHub?’."
      )
    )
    |> redirect(to: @settings)
  end

  defp connect(conn, %{"installation_id" => id, "setup_action" => action})
       when action in ~w(install update) do
    with {:ok, id} when is_integer(id) and id > 0 <- Ecto.Type.cast(:integer, id),
         {:ok, connection} <-
           Classrooms.connect_github_organization(conn.assigns.current_user, id) do
      conn
      |> put_flash(
        :info,
        gettext("%{organization} is connected to your account.", organization: connection.login)
      )
      |> redirect(to: @settings)
    else
      {:error, reason} -> failure(conn, reason)
      _ -> failure(conn, :invalid_installation)
    end
  end

  defp connect(conn, _params), do: failure(conn, :invalid_installation)

  defp allowed?(conn), do: not Demo.enabled?() and Accounts.teacher?(conn.assigns[:current_user])

  defp valid_state?(%{"state" => expected, "issued_at" => issued_at, "user_id" => id}, state, id)
       when is_binary(expected) and is_binary(state) and is_integer(issued_at) do
    age = System.system_time(:second) - issued_at

    age in 0..900 and byte_size(state) == byte_size(expected) and
      Plug.Crypto.secure_compare(expected, state)
  end

  defp valid_state?(_, _, _), do: false

  defp failure(conn, reason) do
    conn
    |> put_flash(:error, AccountComponents.organization_error(reason))
    |> redirect(to: @settings)
  end
end
