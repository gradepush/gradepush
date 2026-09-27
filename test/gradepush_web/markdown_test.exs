defmodule GradePushWeb.MarkdownTest do
  use ExUnit.Case, async: true
  alias GradePushWeb.Markdown

  test "Markdown renders formatting but never scripts, event handlers or executable links" do
    html =
      Markdown.render(
        "## Goal\n\n**Hello**\n\n<script>alert(1)</script>\n\n[x](javascript:alert%281%29)\n\n<img src=x onerror=alert(1)>"
      )
      |> Phoenix.HTML.safe_to_string()

    assert html =~ "<h2>Goal</h2>"
    assert html =~ "<strong>Hello</strong>"
    refute html =~ "<script"
    refute html =~ "onerror"
    refute html =~ "javascript:"
  end
end
