defmodule GradePushWeb.SetupLive do
  @moduledoc false
  use GradePushWeb, :live_view

  alias GradePush.{Accounts, Installation}
  alias GradePushWeb.OnboardingComponents

  @impl true
  def mount(_params, session, socket) do
    locale = if session["locale"] in ~w(en fr), do: session["locale"], else: "en"
    Gettext.put_locale(GradePushWeb.Gettext, locale)
    institution = Accounts.institution()
    configured? = not is_nil(institution)

    {:ok,
     assign(socket,
       page_title:
         if(configured?, do: gettext("Welcome to GradePush"), else: gettext("Set up GradePush")),
       locale: locale,
       setup_browser_nonce: session["setup_browser_nonce"],
       configured?: configured?,
       institution_name: if(institution, do: institution.name),
       installation_requested?: false,
       form: setup_form(),
       trigger_action?: false,
       manifest_action: nil,
       manifest_json: nil,
       error: nil
     )}
  end

  @impl true
  def handle_params(
        %{"setup_action" => action} = params,
        _uri,
        %{assigns: %{configured?: true}} = socket
      )
      when action in ~w(install update request) and is_map_key(params, "state") do
    query =
      params
      |> Map.take(~w(installation_id setup_action state))
      |> Enum.filter(fn {_key, value} -> is_binary(value) end)
      |> URI.encode_query()

    {:noreply, redirect(socket, to: "/github/organizations/callback?" <> query)}
  end

  def handle_params(
        %{"installation_id" => _, "setup_action" => action},
        _uri,
        %{assigns: %{configured?: true}} = socket
      )
      when action in ~w(install update) do
    {:noreply, redirect(socket, to: "/teacher/settings?section=organizations&connect=true")}
  end

  def handle_params(params, _uri, socket) do
    {:noreply,
     assign(socket,
       installation_requested?: socket.assigns.configured? and params["setup_action"] == "request"
     )}
  end

  @impl true
  def handle_event("change_setup", %{"setup" => params}, socket) do
    {:noreply, assign(socket, form: setup_form(params, false), error: nil)}
  end

  def handle_event("begin_setup", %{"setup" => params}, socket) do
    result =
      Installation.begin_setup(
        params["setup_token"],
        params["institution_name"],
        GradePushWeb.Endpoint.url(),
        socket.assigns.setup_browser_nonce,
        app_owner(params)
      )

    case result do
      {:ok, %{action: %{url: url, manifest: manifest}}} ->
        {:noreply,
         assign(socket,
           manifest_action: url,
           manifest_json: manifest,
           form: setup_form(params),
           trigger_action?: true,
           error: nil
         )}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           form: setup_form(params),
           error: setup_error(reason)
         )}
    end
  end

  def handle_event("invalid_setup_token_link", _params, socket),
    do: {:noreply, assign(socket, error: gettext("The setup link is invalid or expired."))}

  @impl true
  def render(assigns) do
    ~H"""
    <OnboardingComponents.frame
      locale={@locale}
      path={if(@installation_requested?, do: "/setup?setup_action=request", else: "/setup")}
      eyebrow={if(@configured?, do: "GradePush", else: gettext("First-time setup"))}
      title={if(@configured?, do: gettext("Welcome to GradePush"), else: gettext("Set up GradePush"))}
      description={
        if(@configured?,
          do: gettext("Your classes, assignments, and code, together in one place."),
          else: gettext("A shared workspace for your institution, connected to GitHub.")
        )
      }
    >
      <:overview>
        <ol :if={!@configured?} class="space-y-[24px]">
          <OnboardingComponents.setup_step number={1} title={gettext("Name your institution")}>
            {gettext("Create the home for your teachers and their classes.")}
          </OnboardingComponents.setup_step>
          <OnboardingComponents.setup_step number={2} title={gettext("Create the GitHub App")}>
            {gettext("We prepare the configuration. You confirm it on GitHub.")}
          </OnboardingComponents.setup_step>
          <OnboardingComponents.setup_step number={3} title={gettext("Sign in as administrator")}>
            {gettext(
              "Your GitHub account becomes the first administrator. You can then invite your colleagues."
            )}
          </OnboardingComponents.setup_step>
        </ol>
      </:overview>
      <.panel_heading>
        <.icon name="hero-building-library" class="size-5 text-brand" />
        <h2 class="min-w-0 break-words">
          {if(@configured?, do: @institution_name, else: gettext("Your institution"))}
        </h2>
      </.panel_heading>
      <div :if={@configured?} class="p-[28px] max-[760px]:p-[22px]">
        <div data-ui="setup-status" class="flex items-center gap-[14px]">
          <span class={[
            "inline-flex size-[40px] shrink-0 items-center justify-center rounded-full",
            if(@installation_requested?,
              do: "bg-brand-soft text-brand",
              else: "bg-success-surface text-success"
            )
          ]}>
            <.icon
              name={if(@installation_requested?, do: "hero-clock", else: "hero-check")}
              class="size-5"
            />
          </span>
          <p class="min-w-0 font-medium">
            {if(@installation_requested?,
              do: gettext("Organization approval required"),
              else: gettext("Your institution is ready.")
            )}
          </p>
        </div>
        <p :if={@installation_requested?} class="mt-[18px] text-[14px] leading-[1.7] text-muted">
          {gettext(
            "An organization owner must approve the GitHub App installation before you can connect it to GradePush."
          )}
        </p>
        <.button
          href={
            if(@installation_requested?,
              do: "/teacher/settings?section=organizations&connect=true",
              else: "/"
            )
          }
          variant="primary"
          class="mt-[24px] w-full"
        >
          {if(@installation_requested?,
            do: gettext("Back to organizations"),
            else: gettext("Continue to GradePush")
          )}<.icon name="hero-arrow-right" class="size-4 shrink-0" />
        </.button>
      </div>
      <div :if={!@configured?} class="p-[28px] max-[760px]:p-[22px]">
        <.notice :if={@error} kind="error" role="alert">{@error}</.notice>
        <form
          id="setup-form"
          phx-hook="SetupToken"
          phx-submit="begin_setup"
          phx-change="change_setup"
          phx-trigger-action={if(@trigger_action?, do: "true")}
          action={@manifest_action}
          method="post"
          target="_top"
          class="grid gap-[22px]"
        >
          <div :if={is_nil(@manifest_action)} class="grid gap-[22px]">
            <.field for={@form[:institution_name].id}>
              {gettext("Institution name")}
              <.input
                id={@form[:institution_name].id}
                name={@form[:institution_name].name}
                value={@form[:institution_name].value}
                autocomplete="organization"
                maxlength="100"
                required
              />
            </.field>
            <.input
              field={@form[:owner_type]}
              type="select"
              label={gettext("GitHub App owner")}
              options={[
                {gettext("My personal GitHub account"), "personal"},
                {gettext("GitHub organization"), "organization"}
              ]}
            />
            <.field :if={@form[:owner_type].value == "organization"} for={@form[:organization].id}>
              {gettext("GitHub organization name")}
              <.input
                id={@form[:organization].id}
                name={@form[:organization].name}
                value={@form[:organization].value}
                placeholder="my-college"
                autocapitalize="none"
                spellcheck="false"
                maxlength="39"
                aria-describedby="setup-owner-description"
                required
              />
              <.field_hint id="setup-owner-description" class="!m-0 font-normal">
                {gettext(
                  "Use its GitHub name, not its URL. You need permission to create an App in this organization."
                )}
              </.field_hint>
            </.field>
            <.field for={@form[:setup_token].id}>
              {gettext("One-time setup token")}
              <.input
                id={@form[:setup_token].id}
                name={@form[:setup_token].name}
                value={@form[:setup_token].value}
                type="password"
                autocomplete="off"
                maxlength="128"
                aria-describedby="setup-token-description"
                required
              />
              <.field_hint id="setup-token-description" class="!m-0 font-normal">
                {gettext("Use the token you set when deploying, or open your private setup link.")}
              </.field_hint>
            </.field>
            <details
              data-ui="setup-token-help"
              class="rounded-[8px] border border-line bg-surface-heading text-[13px]"
            >
              <summary class="cursor-pointer rounded-[8px] px-[16px] py-[14px] font-[550] text-heading">
                {gettext("Where do I find my setup token?")}
              </summary>
              <div class="space-y-[18px] px-[16px] pb-[18px] text-muted leading-[1.65]">
                <div>
                  <h3 class="mb-[4px] font-semibold text-ink">{gettext("Deployment secret")}</h3>
                  <p>
                    {gettext(
                      "Set SETUP_TOKEN in your hosting provider’s secrets before starting GradePush, then enter the same value here. Use a random token of 32 to 128 characters without spaces."
                    )}
                  </p>
                </div>
                <div>
                  <h3 class="mb-[4px] font-semibold text-ink">{gettext("Docker Compose")}</h3>
                  <p>{gettext("Generate a private setup link with this command:")}</p>
                  <code class="mt-[8px] block select-all wrap-anywhere rounded-[6px] border border-line bg-white p-[12px] text-[12px] text-body">docker compose exec app gradepush-setup</code>
                  <p class="mt-[8px]">
                    {gettext("Open the link to fill in the token automatically.")}
                  </p>
                </div>
              </div>
            </details>
            <.button type="submit" variant="primary" class="w-full">
              {gettext("Create GitHub App")}<.icon name="hero-arrow-up-right" />
            </.button>
          </div>
          <.input :if={@manifest_action} type="hidden" name="manifest" value={@manifest_json} />
          <div
            :if={@manifest_action}
            data-ui="setup-progress"
            class="flex items-center gap-[12px] rounded-[8px] border border-line bg-surface-heading p-[18px] text-[14px] text-muted"
            role="status"
            aria-live="polite"
          >
            <.icon name="hero-arrow-path" class="size-5 animate-spin" />
            <span>{gettext("Opening GitHub...")}</span>
          </div>
        </form>
      </div>
    </OnboardingComponents.frame>
    """
  end

  defp setup_form(params \\ %{}, clear_token? \\ true) do
    %{"institution_name" => "", "owner_type" => "personal", "organization" => ""}
    |> Map.merge(Map.take(params, ~w(institution_name owner_type organization)))
    |> Map.put("setup_token", if(clear_token?, do: "", else: Map.get(params, "setup_token", "")))
    |> to_form(as: :setup)
  end

  defp app_owner(params) do
    case Map.get(params, "owner_type", "personal") do
      "personal" -> :personal
      "organization" -> {:organization, params["organization"]}
      _ -> :invalid
    end
  end

  defp setup_error(:invalid_app_owner),
    do: gettext("Choose an App owner and enter a valid GitHub organization name if needed.")

  defp setup_error(:invalid_setup_token), do: gettext("The setup token is invalid.")

  defp setup_error(:invalid_institution_name),
    do: gettext("Enter an institution name of 1 to 100 characters.")

  defp setup_error(:already_configured),
    do: gettext("This installation is already configured.")

  defp setup_error(:setup_in_progress),
    do: gettext("Setup is already in progress in another browser.")

  defp setup_error(reason) when reason in [:public_https_required, :invalid_base_url],
    do: gettext("Use a public HTTPS address for GradePush before creating the GitHub App.")

  defp setup_error(_reason),
    do: gettext("Setup could not start. Check the token and try again.")
end
