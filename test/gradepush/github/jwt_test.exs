defmodule GradePush.GitHub.JWTTest do
  use ExUnit.Case, async: true

  alias GradePush.GitHub.JWT

  test "generates an RS256 App JWT with bounded claims and a verifiable signature" do
    private_key = :public_key.generate_key({:rsa, 2048, 65_537})
    pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, private_key)])

    assert {:ok, token} =
             JWT.generate(%{client_id: "Iv1.application", private_key: pem}, 1_800_000_000)

    [encoded_header, encoded_claims, encoded_signature] = String.split(token, ".")
    header = Jason.decode!(Base.url_decode64!(encoded_header, padding: false))
    claims = Jason.decode!(Base.url_decode64!(encoded_claims, padding: false))
    signature = Base.url_decode64!(encoded_signature, padding: false)

    assert header == %{"alg" => "RS256", "typ" => "JWT"}
    assert claims == %{"exp" => 1_800_000_480, "iat" => 1_799_999_940, "iss" => "Iv1.application"}

    public_key = {:RSAPublicKey, elem(private_key, 2), elem(private_key, 3)}

    assert :public_key.verify(
             encoded_header <> "." <> encoded_claims,
             :sha256,
             signature,
             public_key
           )
  end

  test "rejects an unsupported or malformed private key without exposing it" do
    assert {:error, :invalid_github_app_private_key} =
             JWT.generate(%{client_id: "Iv1.application", private_key: "not a pem"})
  end
end
