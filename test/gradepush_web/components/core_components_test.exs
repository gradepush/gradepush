defmodule GradePushWeb.CoreComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  import Phoenix.Component

  alias GradePushWeb.CoreComponents

  test "avatars without a photo use initials without a broken image" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <CoreComponents.user_avatar src={nil}>AB</CoreComponents.user_avatar>
      """)

    refute html =~ "<img"
    assert html =~ "data-avatar"
    assert html =~ ">AB</span>"
  end

  test "buttons preserve action, submit, and navigation semantics" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <CoreComponents.button phx-click="cancel">Cancel</CoreComponents.button>
      <CoreComponents.button type="submit" name="intent" value="save" disabled>Save</CoreComponents.button>
      <CoreComponents.button patch="/classrooms">Classes</CoreComponents.button>
      <CoreComponents.button href="/export.csv" download>Export</CoreComponents.button>
      """)

    assert html =~ ~s(type="button")
    assert html =~ ~s(phx-click="cancel")
    assert html =~ ~s(type="submit")
    assert html =~ ~s(name="intent")
    assert html =~ ~s(value="save")
    assert html =~ "disabled"
    assert html =~ ~s(data-phx-link="patch")
    assert html =~ ~s(href="/export.csv")
    assert html =~ "download"
  end

  test "standalone selects accept conditional option slots without a value" do
    assigns = %{options: [{"Teacher", "teacher"}, {"Admin", "admin"}]}

    html =
      rendered_to_string(~H"""
      <CoreComponents.input type="select" name="member[role]" label="Role">
        <option :for={{label, value} <- @options} value={value} selected={value == "admin"}>
          {label}
        </option>
      </CoreComponents.input>
      """)

    assert html =~ ~s(for="member_role")
    assert html =~ ~s(id="member_role")
    assert html =~ ~s(value="admin" selected)
  end

  test "form fields retain false overrides and disabled checkboxes disable the hidden fallback" do
    assigns = %{form: to_form(%{"enabled" => true}, as: :settings)}

    html =
      rendered_to_string(~H"""
      <CoreComponents.input
        field={@form[:enabled]}
        type="checkbox"
        value={false}
        label="Enabled"
        disabled
        form="settings"
      />
      """)

    refute html =~ " checked"
    assert html =~ ~s(id="settings_enabled")
    assert html =~ ~s(name="settings[enabled]")
    assert html =~ ~s(type="hidden")
    assert length(Regex.scan(~r/\sdisabled(?:\s|>)/, html)) == 2
    assert length(Regex.scan(~r/form="settings"/, html)) == 2
  end

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
