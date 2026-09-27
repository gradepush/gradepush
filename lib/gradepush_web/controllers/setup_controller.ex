defmodule GradePushWeb.SetupController do
  use GradePushWeb, :controller

  alias GradePush.Installation

  def manifest_callback(conn, %{"code" => code, "state" => state}) do
    callback_url = GradePushWeb.Endpoint.url() <> "/setup/github/auth/callback"
    browser_nonce = get_session(conn, :setup_browser_nonce)

    with {:ok, %{state: next_state}} <-
           Installation.convert_manifest(state, code, browser_nonce),
         {:ok, url} <-
           Installation.setup_authorization_url(next_state, callback_url, browser_nonce) do
      redirect(conn, external: url)
    else
      {:error, _reason} ->
        conn
        |> put_flash(
          :error,
          gettext("GitHub App setup could not be completed. Start setup again.")
        )
        |> redirect(to: "/setup")
    end
  end

  def manifest_callback(conn, _params) do
    conn
    |> put_flash(:error, gettext("GitHub did not return an app setup code. Start setup again."))
    |> redirect(to: "/setup")
  end

  def auth_callback(conn, %{"code" => code, "state" => state}) do
    browser_nonce = get_session(conn, :setup_browser_nonce)

    case Installation.finish_setup(state, code, browser_nonce) do
      {:ok, %{user: user, institution: _institution, session_token: token}} ->
        Plug.CSRFProtection.delete_csrf_token()

        conn
        |> configure_session(renew: true)
        |> clear_session()
        |> put_session(:user_token, token)
        |> put_session(:locale, user.locale || "en")
        |> delete_session(:setup_browser_nonce)
        |> redirect(to: "/admin/platform")

      {:error, _reason} ->
        conn
        |> put_flash(
          :error,
          gettext("GradePush setup could not be completed. Start setup again.")
        )
        |> redirect(to: "/setup")
    end
  end

  def auth_callback(conn, _params) do
    conn
    |> put_flash(:error, gettext("GitHub sign-in was cancelled. Start setup again."))
    |> redirect(to: "/setup")
  end
end
