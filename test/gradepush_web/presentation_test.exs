defmodule GradePushWeb.PresentationTest do
  use ExUnit.Case, async: true

  alias GradePushWeb.Presentation

  test "classroom groups preserve distinct year labels and sort numeric years first" do
    groups =
      Presentation.classroom_groups([
        %{semester: "fall", academic_year: "2026", session: ""},
        %{semester: "fall", academic_year: "26", session: ""},
        %{semester: "winter", academic_year: "AY 2026-27", session: ""},
        %{semester: nil, academic_year: nil, session: ""}
      ])

    assert Enum.map(groups, & &1.label) == [
             "Fall 26",
             "Fall 2026",
             "Winter AY 2026-27",
             "No semester"
           ]
  end
end
