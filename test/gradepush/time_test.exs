defmodule GradePush.TimeTest do
  use ExUnit.Case, async: true

  alias GradePush.Time

  test "deadlines use the institution zone and round-trip in summer and winter" do
    assert {:ok, ~U[2026-09-30 23:59:00Z]} = Time.local_to_utc("2026-09-30T19:59")
    assert {:ok, winter} = Time.local_to_utc("2026-01-30T19:59")
    assert winter == ~U[2026-01-31 00:59:00Z]
    assert Time.format_local(winter) == "2026-01-30T19:59"
  end

  test "nonexistent and ambiguous wall-clock deadlines must be corrected" do
    assert {:error, :nonexistent_time} = Time.local_to_utc("2026-03-08T02:30")
    assert {:error, :ambiguous_time} = Time.local_to_utc("2026-11-01T01:30")
    assert {:error, :invalid_datetime} = Time.local_to_utc("not a date")
    assert {:ok, nil} = Time.local_to_utc("")
  end
end
