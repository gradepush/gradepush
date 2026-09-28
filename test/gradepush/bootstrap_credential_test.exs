defmodule GradePush.BootstrapCredentialTest do
  use GradePush.DataCase, async: true

  import ExUnit.CaptureLog

  alias GradePush.Installation
  alias GradePush.Installation.BootstrapCredential

  test "setup steps are typed and invalid persisted states are rejected" do
    capture_log(fn -> assert {:ok, :created} = Installation.initialize_bootstrap() end)
    credential = Repo.get!(BootstrapCredential, 1)

    assert credential.step == :setup
    refute Ecto.Changeset.cast(credential, %{step: "unexpected"}, [:step]).valid?

    assert_raise Postgrex.Error, ~r/bootstrap_credentials_step_check/, fn ->
      Repo.query!("UPDATE bootstrap_credentials SET step = 'unexpected' WHERE id = 1", [],
        mode: :savepoint
      )
    end

    assert Repo.get!(BootstrapCredential, 1).step == :setup
  end
end
