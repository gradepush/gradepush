defmodule GradePushWeb.CSVTest do
  use ExUnit.Case, async: true
  alias GradePushWeb.CSV

  test "quotes embedded separators and neutralizes formula-shaped student data" do
    assert CSV.encode([["Name", "ID"], ["Doe, Jane", "=1+1"], ["line\nbreak", "  @SUM(A1)"]]) ==
             "\"Name\",\"ID\"\r\n\"Doe, Jane\",\"'=1+1\"\r\n\"line\nbreak\",\"'  @SUM(A1)\"\r\n"

    assert CSV.encode([["She said \"hi\"", nil, 42]]) == "\"She said \"\"hi\"\"\",\"\",\"42\"\r\n"
  end
end
