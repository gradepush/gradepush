defmodule GradePush.SetupOwnerTest do
  use GradePush.DataCase, async: true

  import ExUnit.CaptureLog

  alias GradePush.{Crypto, Installation}
  alias GradePush.Installation.BootstrapCredential

  for {owner, path} <- [
        {:personal, "/settings/apps/new"},
        {{:organization, " My-College "}, "/organizations/My-College/settings/apps/new"}
      ] do
    test "setup registers under #{path}" do
      token = token()
      nonce = random_token()

      assert {:ok, result} =
               Installation.begin_setup(
                 token,
                 "Test College",
                 "https://grades.example",
                 nonce,
                 unquote(Macro.escape(owner))
               )

      uri = URI.parse(result.action.url)
      assert uri.scheme == "https"
      assert uri.host == "github.com"
      assert uri.path == unquote(path)
      assert URI.decode_query(uri.query) == %{"state" => result.state}
      refute result.action.manifest =~ token

      assert {:error, :invalid_setup_state} =
               Installation.convert_manifest(result.state, "manifest-code", random_token())

      assert {:ok, %{state: state}} =
               Installation.convert_manifest(result.state, "manifest-code", nonce)

      assert {:ok, %{institution: institution}} =
               Installation.finish_setup(state, "oauth-code", nonce)

      assert institution.name == "Test College"
    end
  end

  test "invalid owners cannot alter the bootstrap state or inject a redirect destination" do
    token = token()
    original = Repo.get!(BootstrapCredential, 1)

    invalid = [
      nil,
      :unknown,
      {:organization, nil},
      {:organization, ""},
      {:organization, "https://github.com/college"},
      {:organization, "../college"},
      {:organization, "college?redirect=evil"},
      {:organization, "college%2Fsettings"},
      {:organization, "college--name"},
      {:organization, String.duplicate("a", 40)}
    ]

    for owner <- invalid do
      assert {:error, :invalid_app_owner} =
               Installation.begin_setup(
                 token,
                 "Test College",
                 "https://grades.example",
                 random_token(),
                 owner
               )

      assert Repo.get!(BootstrapCredential, 1) == original
    end
  end

  defp token do
    capture_log(fn -> assert {:ok, :created} = Installation.initialize_bootstrap() end)
    credential = Repo.get!(BootstrapCredential, 1)
    {:ok, token} = Crypto.decrypt(credential.token_encrypted, "bootstrap.token")
    token
  end

  defp random_token, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
end
