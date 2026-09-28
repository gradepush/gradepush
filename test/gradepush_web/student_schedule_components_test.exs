defmodule GradePushWeb.StudentScheduleComponentsTest do
  use ExUnit.Case, async: true

  alias GradePushWeb.StudentScheduleComponents, as: Schedule

  test "calendar dates use the institution zone across UTC midnight and year boundaries" do
    early = %{deadline_at: ~U[2027-01-01 02:00:00Z]}
    late = %{deadline_at: ~U[2027-01-01 04:30:00Z]}
    january = %{deadline_at: ~U[2027-01-01 06:00:00Z]}
    undated = %{deadline_at: nil}

    schedule =
      Schedule.prepare(
        [early, late, january, undated],
        %{"view" => "calendar", "month" => "2026-12"},
        ~U[2027-01-01 03:00:00Z]
      )

    assert schedule.today == ~D[2026-12-31]
    assert schedule.days == [{~D[2026-12-31], [early, late]}]
    assert schedule.past == [early]
    assert schedule.upcoming == [late, january]
    assert schedule.undated == [undated]
    assert List.first(hd(schedule.weeks)).date == ~D[2026-11-30]
    assert List.last(List.last(schedule.weeks)).date == ~D[2027-01-03]
  end

  test "malformed calendar parameters fall back safely and leap days remain present" do
    for value <- ["invalid", "2026-13", "0000-01", "9999-12", "2026-01-01", ["2026-01"]] do
      schedule =
        Schedule.prepare([], %{"month" => value, "view" => "invalid"}, ~U[2028-02-03 18:00:00Z])

      assert schedule.month == ~D[2028-02-01]
      assert schedule.view == "list"
      assert Enum.any?(List.flatten(schedule.weeks), &(&1.date == ~D[2028-02-29]))
    end
  end
end
