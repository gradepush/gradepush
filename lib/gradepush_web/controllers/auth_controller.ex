defmodule GradePushWeb.AuthController do
  use GradePushWeb, :controller

  alias GradePush.Accounts
  alias GradePush.Installation

  @oauth_state_lifetime_seconds 10 * 60

  def new(conn, _params) do
    cond do
      is_nil(Accounts.institution()) ->
        redirect(conn, to: "/setup")

      not is_nil(conn.assigns[:current_user]) ->
        redirect(conn, to: safe_return_to(get_session(conn, :return_to)))

      true ->
        state = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
        issued_at = System.system_time(:second)
        callback_url = GradePushWeb.Endpoint.url() <> "/auth/github/callback"

        case Installation.github_authorization_url(state, callback_url) do
          {:ok, url} ->
            conn
            |> put_session(:oauth_state, state)
            |> put_session(:oauth_state_issued_at, issued_at)
            |> redirect(external: url)

          {:error, _reason} ->
            conn
            |> put_flash(
              :error,
              gettext("GitHub sign-in is unavailable. Contact your administrator.")
            )
            |> redirect(to: "/auth/sign-in")
        end
    end
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    expected_state = get_session(conn, :oauth_state)
    issued_at = get_session(conn, :oauth_state_issued_at)
    return_to = get_session(conn, :return_to)
    conn = conn |> delete_session(:oauth_state) |> delete_session(:oauth_state_issued_at)

    if valid_state?(expected_state, state, issued_at) and byte_size(code) <= 2_048 do
      case Installation.authenticate_github_user(code) do
        {:ok, %{user: user, session_token: token}} ->
          Plug.CSRFProtection.delete_csrf_token()

          conn
          |> configure_session(renew: true)
          |> clear_session()
          |> put_session(:user_token, token)
          |> put_session(:locale, user.locale || "en")
          |> redirect(to: safe_return_to(return_to))

        {:error, _reason} ->
          conn
          |> put_flash(:error, gettext("GitHub sign-in could not be completed. Try again."))
          |> redirect(to: "/auth/sign-in")
      end
    else
      conn
      |> delete_session(:return_to)
      |> put_flash(:error, gettext("GitHub sign-in could not be verified. Try again."))
      |> redirect(to: "/auth/sign-in")
    end
  end

  def callback(conn, %{"error" => _error}) do
    conn
    |> delete_session(:oauth_state)
    |> delete_session(:oauth_state_issued_at)
    |> delete_session(:return_to)
    |> put_flash(:error, gettext("GitHub sign-in was cancelled."))
    |> redirect(to: "/auth/sign-in")
  end

  def callback(conn, _params) do
    conn
    |> delete_session(:oauth_state)
    |> delete_session(:oauth_state_issued_at)
    |> delete_session(:return_to)
    |> put_flash(:error, gettext("GitHub sign-in could not be verified. Try again."))
    |> redirect(to: "/auth/sign-in")
  end

  def delete(conn, _params) do
    Accounts.revoke_session(get_session(conn, :user_token))

    conn
    |> configure_session(drop: true)
    |> redirect(to: "/auth/sign-in")
  end

  defp valid_state?(expected, received, issued_at)
       when is_binary(expected) and is_binary(received) and
              byte_size(expected) == byte_size(received) and is_integer(issued_at) do
    now = System.system_time(:second)
    age = now - issued_at

    age in 0..@oauth_state_lifetime_seconds and Plug.Crypto.secure_compare(expected, received)
  end

  defp valid_state?(_expected, _received, _issued_at), do: false

  defp safe_return_to(path) when is_binary(path) and byte_size(path) <= 2048 do
    case URI.parse(path) do
      %URI{scheme: nil, host: nil, userinfo: nil, path: <<"/", second, _::binary>>}
      when second != ?/ and second != ?\\ ->
        path

      %URI{scheme: nil, host: nil, path: "/"} ->
        "/"

      _other ->
        "/"
    end
  end

  defp safe_return_to(_path), do: "/"
end
