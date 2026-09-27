defmodule GradePushWeb.CSV do
  @moduledoc "Encodes downloadable CSV while keeping spreadsheet formulas inert."

  def encode(rows) do
    Enum.map_join(rows, "\r\n", fn row -> Enum.map_join(row, ",", &cell/1) end) <> "\r\n"
  end

  defp cell(nil), do: "\"\""

  defp cell(value) do
    value = to_string(value)
    value = if Regex.match?(~r/\A[\s\x00-\x1f]*[=+@-]/u, value), do: "'" <> value, else: value
    "\"" <> String.replace(value, "\"", "\"\"") <> "\""
  end
end
