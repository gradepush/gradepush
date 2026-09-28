defmodule GradePush.PlatformOperatorsTest do
  use GradePush.DataCase, async: true

  import GradePush.AccountsFixtures
  alias GradePush.Accounts

  test "an operator can transfer access to an existing account independently of institution roles" do
    %{user: owner} = bootstrap_fixture()
    successor = user_fixture(%{login: "successor"})
    assert {:ok, candidate} = Accounts.find_platform_operator_candidate(owner, " @SUCCESSOR ")
    assert candidate.id == successor.id
    assert {:ok, _} = Accounts.grant_platform_operator(owner, successor.id)
    assert {:ok, _} = Accounts.grant_platform_operator(owner, successor.id)
    assert Accounts.operator?(successor)
    refute Accounts.admin?(successor)
    refute Accounts.teacher?(successor)
    assert {:ok, operators} = Accounts.list_platform_operators(successor)
    assert length(operators) == 2

    assert {:ok, _} = Accounts.remove_platform_operator(owner, owner.id)
    refute Accounts.operator?(owner)
    assert Accounts.admin?(owner)
    assert Accounts.teacher?(owner)

    assert {:error, :last_platform_operator} =
             Accounts.remove_platform_operator(successor, successor.id)

    assert {:ok, events} = Accounts.list_audit(successor, :platform)

    assert Enum.map(events, & &1.action) == [
             "platform.operator_removed",
             "platform.operator_granted"
           ]

    assert {:error, :unauthorized} = Accounts.grant_platform_operator(owner, owner.id)
    assert {:error, :unauthorized} = Accounts.remove_platform_operator(owner, successor.id)
    assert {:error, :unauthorized} = Accounts.list_platform_operators(owner)
  end

  test "institution administrators cannot grant platform access and invalid targets change nothing" do
    %{user: owner} = bootstrap_fixture()
    admin = user_fixture()
    teacher_membership_fixture(admin)
    {:ok, _} = Accounts.change_role(owner, admin.id, :admin)
    assert {:error, :unauthorized} = Accounts.grant_platform_operator(admin, admin.id)
    assert {:error, :unauthorized} = Accounts.remove_platform_operator(admin, owner.id)
    assert {:error, :unauthorized} = Accounts.find_platform_operator_candidate(admin, owner.login)
    assert {:error, :unauthorized} = Accounts.list_platform_operators(admin)

    assert {:error, :account_not_found} =
             Accounts.find_platform_operator_candidate(owner, "unknown-user")

    assert {:error, :not_found} = Accounts.grant_platform_operator(owner, -1)
    assert {:error, :last_platform_operator} = Accounts.remove_platform_operator(owner, owner.id)
    assert {:ok, []} = Accounts.list_audit(owner, :platform)
  end
end
