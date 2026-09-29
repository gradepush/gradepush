defmodule GradePushWeb.Metadata do
  @moduledoc "Public sharing metadata and indexing policy for each installation."
  @behaviour Plug

  use Gettext, backend: GradePushWeb.Gettext
  import Plug.Conn

  def init(options), do: options

  def call(conn, _options) do
    register_before_send(conn, fn conn ->
      robots = if conn.status == 200 and public_demo?(conn), do: "index, follow", else: "noindex"
      put_resp_header(conn, "x-robots-tag", robots)
    end)
  end

  def public_demo?(conn) do
    conn.method in ["GET", "HEAD"] and conn.path_info == ["demo"] and GradePush.Demo.enabled?()
  end

  def demo_title, do: gettext("GitHub Classroom alternative")

  def demo_description do
    gettext(
      "GradePush Classroom is an open-source, self-hosted alternative to GitHub Classroom. Explore assignments, GitHub repositories, and automated grading without a GitHub account."
    )
  end

  def for_page(conn, locale) do
    public_demo = public_demo?(conn)
    origin = GradePushWeb.Endpoint.url()

    %{
      public_demo?: public_demo,
      robots: if(public_demo, do: "index, follow", else: "noindex"),
      title:
        if(public_demo, do: demo_title() <> " | GradePush Classroom", else: "GradePush Classroom"),
      description:
        if(public_demo,
          do: demo_description(),
          else:
            gettext(
              "GradePush Classroom is an open-source, self-hosted alternative to GitHub Classroom for managing programming assignments, repositories, and automated feedback."
            )
        ),
      image: origin <> "/images/og-image.png",
      image_alt: gettext("GradePush logo"),
      locale: if(locale == "fr", do: "fr_CA", else: "en_CA"),
      alternate_locale: if(locale == "fr", do: "en_CA", else: "fr_CA"),
      canonical: demo_url(origin, locale),
      alternates: for(language <- ~w(en fr), do: {language, demo_url(origin, language)})
    }
  end

  defp demo_url(origin, locale), do: origin <> "/demo?" <> URI.encode_query(%{"locale" => locale})
end
