defmodule GradePush.Time do
  @moduledoc "Converts institution wall-clock deadlines to UTC without guessing during clock changes."

  def timezone, do: Application.get_env(:gradepush, :timezone, "America/Toronto")

  def local_to_utc(value) when value in [nil, ""], do: {:ok, nil}

  def local_to_utc(value) when is_binary(value) do
    value = if byte_size(value) == 16, do: value <> ":00", else: value

    with {:ok, naive} <- NaiveDateTime.from_iso8601(value),
         {:ok, local} <- DateTime.from_naive(naive, timezone()) do
      DateTime.shift_zone(local, "Etc/UTC")
    else
      {:ambiguous, _, _} -> {:error, :ambiguous_time}
      {:gap, _, _} -> {:error, :nonexistent_time}
      {:error, _} -> {:error, :invalid_datetime}
    end
  end

  def local_to_utc(_), do: {:error, :invalid_datetime}

  def format_local(nil), do: ""

  def format_local(value) do
    value |> DateTime.shift_zone!(timezone()) |> Calendar.strftime("%Y-%m-%dT%H:%M")
  end

  def format_datetime(nil), do: "—"

  def format_datetime(value) do
    value |> DateTime.shift_zone!(timezone()) |> Calendar.strftime("%Y-%m-%d %H:%M %Z")
  end
end
