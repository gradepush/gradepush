defmodule GradePushWeb.CLIAuthorizationLive do
  @moduledoc false
  use GradePushWeb, :live_view

  alias GradePush.{Accounts, CLI, Demo}
  alias GradePushWeb.WorkspaceLayout

  @impl true
  def mount(params, session, socket) do
    locale = if session["locale"] in ~w(en fr), do: session["locale"], else: "en"
    Gettext.put_locale(GradePushWeb.Gettext, locale)
    actor = socket.assigns.current_user

    if Demo.enabled?() or is_nil(actor) or not Accounts.teacher?(actor) do
      {:ok, redirect(socket, to: "/")}
    else
      code =
        case params["user_code"] do
          code when is_binary(code) and byte_size(code) <= 32 -> code
          _ -> ""
        end

      {:ok,
       assign(socket,
         locale: locale,
         path: "/cli/authorize?" <> URI.encode_query(%{"user_code" => code}),
         page_title: gettext("Authorize your terminal"),
         form: to_form(%{"user_code" => code}, as: :cli),
         result: nil,
         error: nil
       )}
    end
  end

  @impl true
  def handle_event(
        "authorize",
        %{"cli" => %{"user_code" => code}, "decision" => decision},
        socket
      )
      when decision in ~w(approve deny) do
    result =
      if decision == "approve",
        do: CLI.approve(socket.assigns.current_user, code),
        else: CLI.deny(socket.assigns.current_user, code)

    case result do
      :ok ->
        {:noreply, assign(socket, result: decision, error: nil)}

      {:error, _} ->
        {:noreply,
         assign(socket,
           error: gettext("This code is invalid or expired. Start login again in your terminal.")
         )}
    end
  end

  def handle_event("authorize", _params, socket) do
    {:noreply, assign(socket, error: gettext("Enter the code displayed in your terminal."))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page public>
      <div class="min-h-screen flex flex-col">
        <WorkspaceLayout.public_header locale={@locale} path={@path} />
        <.page_content>
          <.panel class="mx-auto max-w-[620px]">
            <.panel_heading>
              <.icon name="hero-command-line" class="size-5 text-brand" />
              <h1 class="text-xl font-semibold">{gettext("Authorize your terminal")}</h1>
            </.panel_heading>
            <div class="p-[24px] max-[760px]:p-[18px]">
              <.notice :if={@error} kind="error">{@error}</.notice>
              <div :if={@result} role="status" class="space-y-[16px]">
                <p class="font-semibold text-heading">
                  {if @result == "approve",
                    do: gettext("Terminal authorized"),
                    else: gettext("Request declined")}
                </p>
                <p class="text-muted">
                  {gettext("You can close this page and return to your terminal.")}
                </p>
              </div>
              <.form
                :if={!@result}
                for={@form}
                id="cli-authorization"
                phx-submit="authorize"
                class="space-y-[20px]"
              >
                <p>{gettext("Signed in as @%{login}", login: @current_user.login)}</p>
                <p class="text-muted leading-[1.7]">
                  {gettext(
                    "Allow this terminal to list repositories from your classes. Cloning still requires your GitHub access."
                  )}
                </p>
                <.input
                  field={@form[:user_code]}
                  label={gettext("Terminal code")}
                  required
                  maxlength="32"
                  autocomplete="off"
                  spellcheck="false"
                  class="font-mono text-lg tracking-[.15em]"
                />
                <p class="text-[13px] leading-[1.6] text-muted">
                  {gettext(
                    "Only approve a code displayed in a terminal you opened. Never approve a code sent by someone else."
                  )}
                </p>
                <div class="flex flex-wrap justify-end gap-[10px]">
                  <.button type="submit" name="decision" value="deny">{gettext("Decline")}</.button>
                  <.button type="submit" name="decision" value="approve" variant="primary">{gettext(
                    "Authorize terminal"
                  )}</.button>
                </div>
              </.form>
            </div>
          </.panel>
        </.page_content>
        <WorkspaceLayout.footer context={:public} links={@footer_links} />
      </div>
    </.page>
    """
  end
end
