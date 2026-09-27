defmodule GradePushWeb.SetupLive do
  @moduledoc false
  use GradePushWeb, :live_view

  alias GradePush.Installation
  alias GradePushWeb.WorkspaceLayout

  @impl true
  def mount(_params, session, socket) do
    locale = if session["locale"] in ~w(en fr), do: session["locale"], else: "en"
    Gettext.put_locale(GradePushWeb.Gettext, locale)
    configured? = Installation.configured?()

    {:ok,
     assign(socket,
       page_title: gettext("Set up GradePush"),
       locale: locale,
       setup_browser_nonce: session["setup_browser_nonce"],
       configured?: configured?,
       https_ready?: URI.parse(GradePushWeb.Endpoint.url()).scheme == "https",
       form: to_form(%{"institution_name" => "", "setup_token" => ""}, as: :setup),
       manifest_action: nil,
       manifest_json: nil,
       error: nil
     )}
  end

  @impl true
  def handle_event("begin_setup", %{"setup" => params}, socket) do
    result =
      Installation.begin_setup(
        params["setup_token"],
        params["institution_name"],
        GradePushWeb.Endpoint.url(),
        socket.assigns.setup_browser_nonce
      )

    case result do
      {:ok, %{action: %{url: url, manifest: manifest}}} ->
        {:noreply,
         assign(socket,
           manifest_action: url,
           manifest_json: manifest,
           form:
             to_form(%{"institution_name" => params["institution_name"], "setup_token" => ""},
               as: :setup
             ),
           error: nil
         )}

      {:error, reason} ->
        {:noreply, assign(socket, error: setup_error(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="class-preview">
      <div class="cp-shell">
        <WorkspaceLayout.public_header locale={@locale} path="/setup" />
        <main class="cp-main">
          <section class="cp-admin-panel mx-auto" style="max-width: 720px">
            <div class="cp-admin-panel-heading">
              <.icon name="hero-building-library" class="size-5" />
              <div>
                <h1 class="text-xl font-semibold">{gettext("Set up GradePush")}</h1>
                <p>
                  {gettext("Create the institution for this installation and connect its GitHub App.")}
                </p>
              </div>
            </div>

            <p :if={not @https_ready?} class="cp-admin-panel-note" role="note">
              {gettext(
                "GitHub needs a public HTTPS address for app callbacks and webhooks. Expose this server through HTTPS before setup."
              )}
            </p>

            <div :if={@configured?} class="cp-admin-settings-form">
              <p>{gettext("This GradePush installation is already configured.")}</p>
              <a href="/auth/sign-in" class="cp-button cp-primary" style="margin-top: 16px">
                {gettext("Sign in with GitHub")}
              </a>
            </div>

            <div :if={not @configured?}>
              <.form
                :if={is_nil(@manifest_action)}
                for={@form}
                phx-submit="begin_setup"
                class="cp-admin-settings-form cp-form"
              >
                <label for={@form[:institution_name].id}>
                  {gettext("Institution name")}
                  <input
                    id={@form[:institution_name].id}
                    name={@form[:institution_name].name}
                    value={@form[:institution_name].value}
                    autocomplete="organization"
                    maxlength="100"
                    required
                  />
                </label>
                <label for={@form[:setup_token].id}>
                  {gettext("One-time setup token")}
                  <input
                    id={@form[:setup_token].id}
                    name={@form[:setup_token].name}
                    value={@form[:setup_token].value}
                    type="password"
                    autocomplete="off"
                    maxlength="128"
                    required
                  />
                </label>
                <button type="submit" class="cp-button cp-primary">
                  {gettext("Continue to GitHub App setup")}
                </button>
              </.form>

              <div :if={@manifest_action} class="cp-admin-settings-form">
                <h2>{gettext("Create the GradePush GitHub App")}</h2>
                <p class="cp-field-help">
                  {gettext(
                    "GitHub will register the app and return here to finish setting up your administrator account."
                  )}
                </p>
                <form action={@manifest_action} method="post" target="_top" class="mt-4">
                  <input type="hidden" name="manifest" value={@manifest_json} />
                  <button class="cp-button cp-primary" type="submit">
                    {gettext("Create GitHub App")}
                  </button>
                </form>
              </div>
            </div>

            <p :if={@error} class="cp-error" role="alert">
              {@error}
            </p>
          </section>
        </main>
      </div>
    </div>
    """
  end

  defp setup_error(:invalid_setup_token), do: gettext("The setup token is invalid.")

  defp setup_error(:invalid_institution_name),
    do: gettext("Enter an institution name of 1 to 100 characters.")

  defp setup_error(:already_configured),
    do: gettext("This installation is already configured.")

  defp setup_error(:setup_in_progress),
    do: gettext("Setup is already in progress in another browser.")

  defp setup_error(_reason),
    do: gettext("Setup could not start. Check the token and try again.")
end
