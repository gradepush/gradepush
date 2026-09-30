defmodule GradePush.InstitutionValidationTest do
  use GradePush.DataCase, async: true, group: :institution

  import GradePush.AccountsFixtures

  alias GradePush.Accounts

  test "invalid names return validation errors without changing the institution or audit history" do
    %{user: admin, institution: institution} = bootstrap_fixture()
    {:ok, original_audit} = Accounts.list_audit(admin, :institution)

    for name <- ["", "   ", String.duplicate("a", 101)] do
      assert {:error, %Ecto.Changeset{} = changeset} = Accounts.rename_institution(admin, name)
      assert changeset.errors[:name]
      assert Accounts.institution().name == institution.name
      assert Accounts.list_audit(admin, :institution) == {:ok, original_audit}
    end
  end
end
