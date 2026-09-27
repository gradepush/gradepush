defmodule GradePush.Teaching.Token do
  @moduledoc "Generates opaque invitation tokens and computes their lookup digests."

  def generate do
    raw = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    {raw, :crypto.hash(:sha256, raw)}
  end

  def digest(token) when is_binary(token), do: :crypto.hash(:sha256, token)
  def digest(_), do: :crypto.hash(:sha256, "invalid")
end
