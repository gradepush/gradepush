defmodule GradePush.CryptoTest do
  use ExUnit.Case, async: true
  import Bitwise

  alias GradePush.Crypto

  test "credential encryption authenticates both ciphertext and purpose" do
    assert {:ok, encrypted} = Crypto.encrypt("github-secret", "github_app.client_secret")
    assert {:ok, "github-secret"} = Crypto.decrypt(encrypted, "github_app.client_secret")
    assert {:error, :authentication_failed} = Crypto.decrypt(encrypted, "github_app.private_key")

    <<first, rest::binary>> = encrypted

    tampered =
      <<first, bxor(:binary.at(rest, 12), 1),
        binary_part(rest, 13, byte_size(rest) - 13)::binary>>

    assert {:error, :authentication_failed} = Crypto.decrypt(tampered, "github_app.client_secret")
  end

  test "token hashes compare without accepting values of different lengths" do
    hash = Crypto.hash("session-token")

    assert Crypto.secure_compare(hash, hash)
    refute Crypto.secure_compare(hash, Crypto.hash("other-token"))
    refute Crypto.secure_compare(hash, "short")
  end
end
