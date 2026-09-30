defmodule GradePushWeb.ErrorJSONTest do
  use GradePushWeb.ConnCase, async: true, group: :institution

  test "renders 404" do
    assert GradePushWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert GradePushWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
