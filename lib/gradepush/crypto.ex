defmodule GradePush.Crypto do
  @moduledoc """
  Encrypts credentials that must be recovered for GitHub API calls.

  Ciphertexts are versioned and authenticated with a purpose-specific value so a
  stored value cannot be moved between credential fields undetected.
  """

  @version 1
  @nonce_size 12
  @tag_size 16

  def encrypt(value, purpose) when is_binary(value) and is_binary(purpose) do
    with {:ok, key} <- encryption_key() do
      nonce = :crypto.strong_rand_bytes(@nonce_size)

      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, value, purpose, @tag_size, true)

      {:ok, <<@version, nonce::binary, tag::binary, ciphertext::binary>>}
    end
  rescue
    _error -> {:error, :encryption_failed}
  end

  def decrypt(
        <<@version, nonce::binary-size(@nonce_size), tag::binary-size(@tag_size),
          ciphertext::binary>>,
        purpose
      )
      when is_binary(purpose) do
    with {:ok, key} <- encryption_key(),
         value when is_binary(value) <-
           :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, ciphertext, purpose, tag, false) do
      {:ok, value}
    else
      nil -> {:error, :authentication_failed}
      {:error, _reason} = error -> error
      _other -> {:error, :authentication_failed}
    end
  rescue
    _error -> {:error, :authentication_failed}
  end

  def decrypt(_ciphertext, _purpose), do: {:error, :invalid_ciphertext}

  def hash(value) when is_binary(value), do: :crypto.hash(:sha256, value)

  def secure_compare(left, right)
      when is_binary(left) and is_binary(right) and byte_size(left) == byte_size(right) do
    Plug.Crypto.secure_compare(left, right)
  end

  def secure_compare(_left, _right), do: false

  defp encryption_key do
    case Application.get_env(:gradepush, __MODULE__, [])
         |> Keyword.get(:credential_encryption_key) do
      key when is_binary(key) and byte_size(key) == 32 -> {:ok, key}
      _other -> {:error, :encryption_key_unavailable}
    end
  end
end
