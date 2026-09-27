defmodule GradePushWeb.Markdown do
  @moduledoc false

  def render(text, heading_offset \\ 0) do
    text
    |> MDEx.parse_document!(extension: [table: true, strikethrough: true])
    |> MDEx.traverse_and_update(fn
      %MDEx.Heading{level: level} = heading -> %{heading | level: min(level + heading_offset, 6)}
      node -> node
    end)
    |> MDEx.to_html!(
      render: [unsafe: false],
      sanitize: MDEx.Document.default_sanitize_options()
    )
    |> Phoenix.HTML.raw()
  end
end
