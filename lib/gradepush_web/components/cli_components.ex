defmodule GradePushWeb.CLIComponents do
  @moduledoc "Installation and cloning commands for the GradePush CLI."
  use GradePushWeb, :html

  attr :classroom, :string, required: true
  attr :assignment, :string, default: nil
  attr :server, :string, required: true
  attr :demo, :boolean, default: false

  def clone_instructions(assigns) do
    assigns = assign(assigns, :clone_command, clone_command(assigns))

    ~H"""
    <div class="space-y-[16px] text-[14px] leading-[1.6]">
      <p class="text-muted">
        {gettext(
          "Download repositories into folders named after their GitHub repositories. Existing folders are skipped."
        )}
      </p>
      <p :if={@demo} class="text-[13px] text-muted">
        {gettext("Commands are shown as examples. CLI access is unavailable in demo mode.")}
      </p>
      <ol class="space-y-[16px]">
        <li>
          <h3 class="mb-[8px] font-semibold">{gettext("1. Install the extension")}</h3>
          <p class="mb-[8px] text-[13px] text-muted">
            <a
              href="https://cli.github.com/"
              target="_blank"
              rel="noopener noreferrer"
              class="text-brand underline underline-offset-2"
            >{gettext("GitHub CLI")}</a>
            {gettext("and Git must be installed.")}
          </p>
          <.command id="cli-install" command="gh extension install gradepush/gh-gradepush" />
        </li>
        <li>
          <h3 class="mb-[8px] font-semibold">{gettext("2. Sign in")}</h3>
          <div class="space-y-[8px]">
            <.command id="cli-github-login" command="gh auth login" />
            <.command
              id="cli-login"
              command={"gh gradepush login --server " <> quote_argument(@server)}
            />
          </div>
        </li>
        <li>
          <h3 class="mb-[8px] font-semibold">{gettext("3. Clone the repositories")}</h3>
          <.command id="cli-clone" command={@clone_command} />
        </li>
      </ol>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :command, :string, required: true

  def command(assigns) do
    ~H"""
    <GradePushWeb.ClipboardComponents.copy_field
      id={@id}
      value={@command}
      label={gettext("Copy command")}
    />
    """
  end

  defp clone_command(assigns) do
    "gh gradepush clone --server " <>
      quote_argument(assigns.server) <>
      " --classroom " <>
      quote_argument(assigns.classroom) <>
      if(assigns.assignment, do: " --assignment " <> quote_argument(assigns.assignment), else: "")
  end

  defp quote_argument(value) do
    if Regex.match?(~r/\A[a-zA-Z0-9._:\/-]+\z/, value),
      do: value,
      else: "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
  end
end
