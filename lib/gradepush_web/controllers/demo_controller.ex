defmodule GradePushWeb.DemoController do
  use GradePushWeb, :controller

  alias GradePush.Accounts
  alias GradePush.Demo

  def create(conn, %{"demo" => %{"role" => role}}), do: create(conn, %{"role" => role})

  def create(conn, %{"role" => role}) when role in ["teacher", "student"] do
    if Demo.enabled?() do
      demo_role = if role == "student", do: :student, else: :teacher
      sign_in_demo_user(conn, demo_role, locale(conn))
    else
      send_resp(conn, :not_found, "Not found")
    end
  end

  def create(conn, _params) do
    if Demo.enabled?() do
      conn
      |> put_flash(:error, gettext("Choose a demo role to continue."))
      |> redirect(to: "/demo")
    else
      send_resp(conn, :not_found, "Not found")
    end
  end

  defp locale(%Plug.Conn{params: %{"locale" => locale}}) when locale in ~w(en fr), do: locale
  defp locale(conn), do: get_session(conn, :locale) || "en"

  defp sign_in_demo_user(conn, role, locale) do
    with {:ok, user} <- Demo.user_for_role(role),
         {:ok, token} <- Accounts.create_session(user, lifetime_seconds: 6 * 60 * 60) do
      Accounts.revoke_session(get_session(conn, :user_token))
      Plug.CSRFProtection.delete_csrf_token()

      conn
      |> configure_session(renew: true)
      |> clear_session()
      |> put_session(:user_token, token)
      |> put_session(:locale, locale)
      |> put_session(:ui_preview, false)
      |> redirect(to: if(role == :student, do: "/student/classrooms", else: "/classrooms"))
    else
      {:error, _reason} ->
        conn
        |> put_flash(:error, gettext("The demo is not ready. Try again shortly."))
        |> redirect(to: "/demo")
    end
  end
end
