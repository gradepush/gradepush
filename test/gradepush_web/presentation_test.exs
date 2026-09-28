defmodule GradePushWeb.PresentationTest do
  use ExUnit.Case, async: true

  alias GradePushWeb.Presentation

  test "points round to the nearest whole number without trailing decimals" do
    for {value, expected} <- [
          {Decimal.new("100.00"), "100"},
          {Decimal.new("12.49"), "12"},
          {Decimal.new("12.50"), "13"},
          {Decimal.new("0.00"), "0"},
          {"99.99", "100"},
          {0, "0"},
          {12.5, "13"}
        ] do
      assert Presentation.points(value) == expected
    end
  end

  test "classroom groups preserve distinct year labels and sort numeric years first" do
    groups =
      Presentation.classroom_groups([
        %{semester: :fall, academic_year: "2026"},
        %{semester: :fall, academic_year: "26"},
        %{semester: :winter, academic_year: "AY 2026-27"},
        %{semester: nil, academic_year: nil}
      ])

    assert Enum.map(groups, & &1.label) == [
             "Fall 26",
             "Fall 2026",
             "Winter AY 2026-27",
             "No semester"
           ]
  end

  test "semester labels follow the interface language" do
    classroom = %{semester: :fall, academic_year: "26"}

    assert Gettext.with_locale(GradePushWeb.Gettext, "fr", fn ->
             Presentation.classroom_term(classroom)
           end) == "Automne 26"

    assert Gettext.with_locale(GradePushWeb.Gettext, "en", fn ->
             Presentation.classroom_term(classroom)
           end) == "Fall 26"
  end

  test "human dates use the requested locale and the configured local timezone" do
    assert Presentation.datetime(~U[2026-09-18 17:31:00Z], "fr") == "18 septembre 2026 à 13:31"
    assert Presentation.datetime(~U[2026-09-18 17:31:00Z], "en") == "September 18, 2026 at 13:31"
    assert Presentation.datetime(~U[2026-01-01 02:00:00Z], "fr") == "31 décembre 2025 à 21:00"
    assert Presentation.datetime(nil, "fr") == "—"
  end
end
