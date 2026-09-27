defmodule GradePushWeb.PreviewRoutesTest do
  use GradePushWeb.ConnCase

  test "discarded prototype routes are not exposed", %{conn: conn} do
    for path <-
          ~w(/student /institution /instance /settings /teacher/classrooms /teacher/review/amelie) do
      assert conn |> get(path) |> response(404) =~ "Not Found"
    end
  end
end
