defmodule GradePushWeb.Markdown do
  @moduledoc false

  def render(text) do
    text
    |> MDEx.to_html!(
      extension: [table: true, strikethrough: true],
      render: [unsafe: false],
      sanitize: MDEx.Document.default_sanitize_options()
    )
    |> Phoenix.HTML.raw()
  end
end
