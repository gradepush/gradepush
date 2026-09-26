defmodule GradePushWeb.Plugs.Locale do
  @moduledoc "Selects an allowed interface language and remembers it in the browser session."
  import Plug.Conn

  @locales ~w(en fr)

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_query_params(conn)
    requested = conn.query_params["locale"]
    saved = get_session(conn, :locale)

    locale =
      cond do
        requested in @locales -> requested
        saved in @locales -> saved
        true -> "en"
      end

    Gettext.put_locale(GradePushWeb.Gettext, locale)

    conn
    |> put_session(:locale, locale)
    |> assign(:locale, locale)
  end
end
