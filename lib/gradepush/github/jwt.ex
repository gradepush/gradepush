defmodule GradePush.GitHub.JWT do
  @moduledoc false

  def generate(credentials, now \\ System.system_time(:second)) do
    issuer =
      Map.get(credentials, :client_id) || Map.get(credentials, "client_id") ||
        Map.get(credentials, :app_id) || Map.get(credentials, "app_id")

    pem = Map.get(credentials, :private_key) || Map.get(credentials, "private_key")

    with true <- is_binary(issuer) and issuer != "",
         true <- is_binary(pem) and pem != "",
         {:ok, private_key} <- decode_private_key(pem),
         {:ok, token} <- sign(issuer, private_key, now) do
      {:ok, token}
    else
      false -> {:error, :incomplete_github_app_credentials}
      {:error, _reason} -> {:error, :invalid_github_app_private_key}
    end
  end

  defp decode_private_key(pem) do
    case :public_key.pem_decode(pem) do
      [entry | _] ->
        case :public_key.pem_entry_decode(entry) do
          {:RSAPrivateKey, _, _, _, _, _, _, _, _, _, _} = key -> {:ok, key}
          _ -> {:error, :unsupported_private_key}
        end

      [] ->
        {:error, :invalid_pem}
    end
  rescue
    _ -> {:error, :invalid_pem}
  end

  defp sign(issuer, private_key, now) do
    header = encode(%{alg: "RS256", typ: "JWT"})
    claims = encode(%{iat: now - 60, exp: now + 8 * 60, iss: issuer})
    message = header <> "." <> claims

    signature = :public_key.sign(message, :sha256, private_key)
    {:ok, message <> "." <> Base.url_encode64(signature, padding: false)}
  rescue
    _ -> {:error, :jwt_signing_failed}
  end

  defp encode(value), do: value |> Jason.encode!() |> Base.url_encode64(padding: false)
end
