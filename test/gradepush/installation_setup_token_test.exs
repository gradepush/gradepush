defmodule GradePush.InstallationSetupTokenTest do
  use GradePush.DataCase, async: true, group: :institution

  import ExUnit.CaptureLog
  import GradePush.AccountsFixtures

  alias GradePush.{Crypto, Installation}
  alias GradePush.Installation.BootstrapCredential

  test "setup rejects HTTP and local addresses before locking the bootstrap flow" do
    token = random_token()
    capture_log(fn -> assert {:ok, :created} = Installation.initialize_bootstrap(token) end)
    original = Repo.get!(BootstrapCredential, 1)

    for url <- [
          "http://grades.example",
          "https://localhost:4108",
          "https://LOCALHOST.",
          "https://app.localhost",
          "https://school.local",
          "https://127.0.0.1",
          "https://127.1.2.3",
          "https://10.0.0.1",
          "https://192.168.1.4",
          "https://172.16.0.1",
          "https://169.254.1.1",
          "https://[::1]",
          "https://[::ffff:127.0.0.1]",
          "https://[fd00::1]"
        ] do
      refute Installation.public_setup_url?(url)

      assert {:error, :public_https_required} =
               Installation.begin_setup(token, "Test College", url, random_token())
    end

    assert Repo.get!(BootstrapCredential, 1) == original
    assert Installation.public_setup_url?("https://grades.example")
    assert Installation.public_setup_url?("https://test.trycloudflare.com")
    refute Installation.public_setup_url?(nil)
    refute Installation.public_setup_url?("not a URL")
  end

  test "deployment tokens are encrypted, accepted, and never printed in startup logs" do
    token = random_token()
    log = capture_log(fn -> assert {:ok, :created} = Installation.initialize_bootstrap(token) end)
    refute log =~ token
    credential = Repo.get!(BootstrapCredential, 1)
    assert credential.token_hash == Crypto.hash(token)
    refute credential.token_encrypted == token
    assert {:ok, ^token} = Crypto.decrypt(credential.token_encrypted, "bootstrap.token")

    assert {:ok, _} =
             Installation.begin_setup(
               token,
               "Test College",
               "https://grades.example",
               random_token()
             )

    in_progress = Repo.get!(BootstrapCredential, 1)
    assert {:ok, :existing} = Installation.initialize_bootstrap(token)
    assert Repo.get!(BootstrapCredential, 1) == in_progress
    log = capture_log(fn -> assert {:ok, :existing} = Installation.initialize_bootstrap(nil) end)
    refute log =~ token
  end

  test "changing the deployment token invalidates the old token and pending setup state" do
    original = random_token()
    replacement = random_token()
    nonce = random_token()
    assert {:ok, :created} = Installation.initialize_bootstrap(original)

    assert {:ok, %{state: state}} =
             Installation.begin_setup(original, "Test College", "https://grades.example", nonce)

    assert {:ok, :created} = Installation.initialize_bootstrap(replacement)

    assert {:error, :invalid_setup_token} =
             Installation.begin_setup(original, "Test College", "https://grades.example", nonce)

    assert {:error, :invalid_setup_state} =
             Installation.convert_manifest(state, "test-code", nonce)

    assert {:ok, _} =
             Installation.begin_setup(
               replacement,
               "Test College",
               "https://grades.example",
               nonce
             )
  end

  test "invalid configured tokens fail without writing a credential or leaking their value" do
    for token <- [
          "short",
          String.duplicate("a", 129),
          String.duplicate(" ", 32),
          random_token() <> "\n"
        ] do
      log =
        capture_log(fn ->
          assert {:error, :invalid_configured_setup_token} =
                   Installation.initialize_bootstrap(token)
        end)

      refute log =~ token
      refute Repo.get(BootstrapCredential, 1)
    end
  end

  test "a deployment token cannot reopen a configured installation" do
    configured_gradepush_fixture()
    token = random_token()
    assert {:ok, :configured} = Installation.initialize_bootstrap(token)
    refute Repo.get(BootstrapCredential, 1)
    assert {:error, :setup_not_available} = Installation.setup_link("https://grades.example")

    assert {:error, :setup_not_available} =
             Installation.begin_setup(
               token,
               "Other College",
               "https://grades.example",
               random_token()
             )
  end

  defp random_token, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
end
