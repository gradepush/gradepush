defmodule GradePushWeb.CoreComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias GradePushWeb.CoreComponents

  test "input errors preserve hint descriptions and expose an accessible error target" do
    for type <- ~w(text textarea select checkbox) do
      html =
        render_component(&CoreComponents.input/1,
          id: "field",
          name: "field",
          type: type,
          label: "Field",
          value: "",
          options: [],
          errors: ["is invalid"],
          "aria-describedby": "field-help"
        )

      assert html =~ ~s(aria-invalid="true")
      assert html =~ ~s(aria-describedby="field-help field-errors")
      assert html =~ ~s(id="field-errors")
      assert html =~ "is invalid"
    end
  end

  test "valid inputs do not announce an error target" do
    html =
      render_component(&CoreComponents.input/1,
        id: "field",
        name: "field",
        value: "valid",
        label: "Field"
      )

    refute html =~ ~s(aria-invalid="true")
    refute html =~ "field-errors"
  end
end
