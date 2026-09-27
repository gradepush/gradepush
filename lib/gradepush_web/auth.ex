defmodule GradePushWeb.Auth do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  alias GradePush.Accounts
  alias GradePush.Accounts.User

  @session_guard_interval 12 * 60 * 60 * 1_000

  @impl Plug
  def init(options), do: options

  @impl Plug
  def call(conn, :fetch_current_user) do
    conn = fetch_query_params(conn)
    token = get_session(conn, :user_token)
    user = Accounts.get_user_by_session_token(token)
    preview? = is_nil(user) and preview_enabled?(conn)
    conn = ensure_setup_browser_nonce(conn)

    conn
    |> remember_return_to(user, preview?)
    |> assign(:current_user, user)
    |> assign(:preview?, preview?)
  end

  def on_mount(:current_user, _params, session, socket), do: load_user(session, socket)

  def on_mount(:require_authenticated_user, _params, session, socket) do
    case load_user(session, socket) do
      {:halt, socket} ->
        {:halt, socket}

      {:cont, %{assigns: %{current_user: %User{}}} = socket} ->
        {:cont, socket}

      {:cont, %{assigns: %{preview?: true}} = socket} ->
        {:cont, socket}

      {:cont, socket} ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(
           :error,
           Gettext.gettext(GradePushWeb.Gettext, "Sign in with GitHub to continue.")
         )
         |> Phoenix.LiveView.redirect(to: "/auth/sign-in")}
    end
  end

  def on_mount(:require_teacher, _params, session, socket) do
    case load_user(session, socket) do
      {:halt, socket} ->
        {:halt, socket}

      {:cont, %{assigns: %{current_user: %User{} = user}} = socket} ->
        if Accounts.teacher?(user), do: {:cont, socket}, else: access_denied(socket)

      {:cont, %{assigns: %{preview?: true}} = socket} ->
        {:cont, socket}

      {:cont, socket} ->
        {:halt, Phoenix.LiveView.redirect(socket, to: "/auth/sign-in")}
    end
  end

  def on_mount(:require_student, _params, session, socket) do
    case load_user(session, socket) do
      {:halt, socket} ->
        {:halt, socket}

      {:cont, %{assigns: %{current_user: %User{} = user}} = socket} ->
        if Accounts.student?(user), do: {:cont, socket}, else: access_denied(socket)

      {:cont, %{assigns: %{preview?: true}} = socket} ->
        {:cont, socket}

      {:cont, socket} ->
        {:halt, Phoenix.LiveView.redirect(socket, to: "/auth/sign-in")}
    end
  end

  def on_mount(:require_admin, _params, session, socket) do
    require_role(session, socket, &Accounts.admin?/1)
  end

  def on_mount(:require_operator, _params, session, socket) do
    require_role(session, socket, &Accounts.operator?/1)
  end

  def on_mount(_hook, _params, _session, socket), do: {:cont, socket}

  def preview?(%Plug.Conn{} = conn) do
    user = conn.assigns[:current_user]
    is_nil(user) and preview_enabled?(conn)
  end

  def preview?(session) when is_map(session) do
    is_nil(Map.get(session, "user_token")) and preview_enabled?(session)
  end

  defp load_user(session, socket) do
    set_session_locale(session)
    {user, preview?} = session_identity(session)
    socket = Phoenix.Component.assign(socket, current_user: user, preview?: preview?)

    if user && Phoenix.LiveView.connected?(socket) do
      token = Map.get(session, "user_token")

      case Accounts.watch_session(token) do
        {:ok, expires_at} -> {:cont, attach_session_guard(socket, token, expires_at)}
        {:error, _reason} -> {:halt, Phoenix.LiveView.redirect(socket, to: "/auth/sign-in")}
      end
    else
      {:cont, socket}
    end
  end

  defp session_identity(session) do
    user = Accounts.get_user_by_session_token(Map.get(session, "user_token"))
    {user, is_nil(user) and preview_enabled?(session)}
  end

  defp preview_enabled?(%Plug.Conn{} = conn) do
    preview_configured?() and
      get_session(conn, :ui_preview) != false and get_session(conn, "ui_preview") != false
  end

  defp preview_enabled?(session) when is_map(session) do
    preview_configured?() and
      Map.get(session, "ui_preview", Map.get(session, :ui_preview, true)) != false
  end

  defp preview_configured? do
    Application.get_env(:gradepush, :ui_preview, false) and
      not Application.get_env(:gradepush, :demo_mode, false)
  end

  defp remember_return_to(conn, user, preview?) do
    if is_nil(user) and not preview? and protected_path?(conn.request_path) do
      target = local_target(conn)
      put_session(conn, :return_to, target)
    else
      conn
    end
  end

  defp protected_path?(path) do
    String.starts_with?(path, ["/join/", "/student/", "/classrooms"])
  end

  defp local_target(conn) do
    query = if conn.query_string == "", do: "", else: "?" <> conn.query_string
    target = conn.request_path <> query

    case URI.parse(target) do
      %URI{scheme: nil, host: nil, path: "/" <> _} -> target
      _other -> "/"
    end
  end

  defp require_role(session, socket, predicate) do
    case load_user(session, socket) do
      {:halt, socket} ->
        {:halt, socket}

      {:cont, %{assigns: %{current_user: %User{} = user}} = socket} ->
        if predicate.(user), do: {:cont, socket}, else: access_denied(socket)

      {:cont, %{assigns: %{preview?: true}} = socket} ->
        {:cont, socket}

      {:cont, socket} ->
        {:halt, Phoenix.LiveView.redirect(socket, to: "/auth/sign-in")}
    end
  end

  defp access_denied(socket) do
    {:halt,
     socket
     |> Phoenix.LiveView.put_flash(
       :error,
       Gettext.gettext(GradePushWeb.Gettext, "You do not have access to this workspace.")
     )
     |> Phoenix.LiveView.redirect(to: "/")}
  end

  defp set_session_locale(session) do
    case Map.get(session, "locale", Map.get(session, :locale)) do
      locale when locale in ["en", "fr"] -> Gettext.put_locale(GradePushWeb.Gettext, locale)
      _other -> :ok
    end
  end

  defp attach_session_guard(socket, token, expires_at) do
    check_in = next_session_check(expires_at)
    Process.send_after(self(), :gradepush_session_expiration_check, check_in)

    Phoenix.LiveView.attach_hook(socket, :gradepush_session_guard, :handle_info, fn
      :gradepush_session_revoked, socket ->
        {:halt, Phoenix.LiveView.redirect(socket, to: "/auth/sign-in")}

      :gradepush_session_expiration_check, socket ->
        case Accounts.get_user_by_session_token(token) do
          nil ->
            {:halt, Phoenix.LiveView.redirect(socket, to: "/auth/sign-in")}

          _user ->
            Process.send_after(
              self(),
              :gradepush_session_expiration_check,
              next_session_check(expires_at)
            )

            {:cont, socket}
        end

      _message, socket ->
        {:cont, socket}
    end)
  end

  defp next_session_check(expires_at) do
    max(
      min(DateTime.diff(expires_at, DateTime.utc_now(), :millisecond), @session_guard_interval),
      1
    )
  end

  defp ensure_setup_browser_nonce(%Plug.Conn{request_path: "/setup"} = conn) do
    case get_session(conn, :setup_browser_nonce) do
      nonce when is_binary(nonce) and byte_size(nonce) in 32..128 ->
        conn

      _other ->
        nonce = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
        put_session(conn, :setup_browser_nonce, nonce)
    end
  end

  defp ensure_setup_browser_nonce(conn), do: conn
end
