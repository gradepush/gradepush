defmodule GradePushWeb.MarkdownTest do
  use ExUnit.Case, async: true

  alias GradePushWeb.Markdown

  test "embedded instructions keep headings below their section without changing code blocks" do
    html =
      GradePushWeb.Markdown.render("# Goal\n\n## Steps\n\n```text\n# literal\n```", 2)
      |> Phoenix.HTML.safe_to_string()

    assert html =~ "<h3>Goal</h3>"
    assert html =~ "<h4>Steps</h4>"
    assert html =~ "# literal"
    refute html =~ "<h1>"
  end

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
