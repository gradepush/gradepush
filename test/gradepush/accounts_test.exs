defmodule GradePush.AccountsTest do
  use GradePush.DataCase, async: true

  import ExUnit.CaptureLog
  import GradePush.AccountsFixtures

  alias GradePush.Accounts
  alias GradePush.Accounts.{InstitutionInvitation, UserSession}
  alias GradePush.Crypto
  alias GradePush.GitHub.Fake
  alias GradePush.Installation
  alias GradePush.Installation.BootstrapCredential

  test "sessions store only a hash, expire, and notify live sessions when revoked" do
    user = user_fixture()
    assert {:ok, token} = Accounts.create_session(user)
    token_hash = Crypto.hash(token)
    session = Repo.get_by!(UserSession, token_hash: token_hash)

    assert session.token_hash == token_hash
    refute session.token_hash == token
    assert Accounts.get_user_by_session_token(token).id == user.id
    assert {:ok, _expiry} = Accounts.watch_session(token)

    assert :ok = Accounts.revoke_session(token)
    assert_receive :gradepush_session_revoked
    assert is_nil(Accounts.get_user_by_session_token(token))

    assert {:ok, expired_token} = Accounts.create_session(user)
    expired_hash = Crypto.hash(expired_token)
    expired_at = DateTime.add(DateTime.utc_now(), -1, :second)

    Repo.update_all(
      from(session in UserSession, where: session.token_hash == ^expired_hash),
      set: [expires_at: expired_at]
    )

    assert is_nil(Accounts.get_user_by_session_token(expired_token))
  end

  test "student profiles are institution-scoped and can be loaded as a batch" do
    %{user: teacher} = bootstrap_fixture()
    student_one = user_fixture()
    student_two = user_fixture()
    teacher_membership_fixture(teacher)

    assert {:ok, _} = Accounts.enroll_student(student_one, %{name: "Camille", student_id: "1001"})
    assert {:ok, _} = Accounts.enroll_student(student_two, %{name: "Noémie", student_id: "1002"})

    [one, two, teacher_with_profile] =
      Accounts.with_student_profiles([student_one, student_two, teacher])

    assert {one.student_name, one.student_id} == {"Camille", "1001"}
    assert {two.student_name, two.student_id} == {"Noémie", "1002"}
    assert is_nil(teacher_with_profile.student_name)
    assert Accounts.student?(student_one)
    refute Accounts.student?(teacher)
  end

  test "teacher invitation acceptance is single-use and audited" do
    %{user: admin} = bootstrap_fixture()
    invitee = user_fixture()

    assert {:ok, %{invitation: %InstitutionInvitation{}, token: token}} =
             Accounts.create_teacher_invitation(admin)

    assert {:ok, %{institution_name: "Test Institution"}} =
             Accounts.lookup_teacher_invitation(token)

    assert {:ok, membership} = Accounts.accept_teacher_invitation(invitee, token)
    assert membership.role == :teacher
    assert Accounts.teacher?(invitee)
    assert {:error, :invalid_invitation} = Accounts.accept_teacher_invitation(invitee, token)

    assert {:ok, [%{action: "teacher.invitation.accepted", actor_name: actor_name} | _]} =
             Accounts.list_audit(admin, :institution)

    assert actor_name == invitee.name
  end

  test "institution admins can promote and demote teachers but cannot remove the last admin" do
    %{user: admin} = bootstrap_fixture()
    teacher = user_fixture()
    teacher_membership_fixture(teacher)

    assert {:error, :unauthorized} = Accounts.change_role(teacher, admin.id, :teacher)
    assert {:error, :unauthorized} = Accounts.remove_teacher(teacher, admin.id)
    assert {:error, :last_administrator} = Accounts.change_role(admin, admin.id, :teacher)
    assert {:error, :cannot_remove_self} = Accounts.remove_teacher(admin, admin.id)

    assert {:ok, promoted} = Accounts.change_role(admin, teacher.id, :admin)
    assert Accounts.admin?(promoted)
    assert Accounts.teacher?(promoted)

    assert {:ok, demoted} = Accounts.change_role(admin, teacher.id, :teacher)
    refute Accounts.admin?(demoted)
    assert Accounts.teacher?(demoted)

    assert {:ok, events} = Accounts.list_audit(admin, :institution)
    actions = Enum.map(events, & &1.action)
    assert "teacher.admin_granted" in actions
    assert "teacher.admin_revoked" in actions
  end

  test "bootstrap state requires its browser nonce and the token is encrypted at rest" do
    capture_log(fn -> assert {:ok, :created} = Installation.initialize_bootstrap() end)
    credential = Repo.get!(BootstrapCredential, 1)
    assert {:ok, token} = Crypto.decrypt(credential.token_encrypted, "bootstrap.token")
    refute credential.token_hash == token

    nonce = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    other_nonce = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    assert {:ok, %{state: state, action: %{manifest: manifest}}} =
             Installation.begin_setup(
               token,
               "Test Institution",
               "https://gradepush.example",
               nonce
             )

    assert {:ok, manifest_payload} = Jason.decode(manifest)
    assert manifest_payload["public"]
    assert "push" in manifest_payload["default_events"]
    assert "https://gradepush.example/auth/github/callback" in manifest_payload["callback_urls"]

    assert manifest_payload["default_permissions"] == %{
             "actions" => "read",
             "administration" => "write",
             "contents" => "write",
             "members" => "read",
             "metadata" => "read",
             "workflows" => "write"
           }

    assert {:error, :setup_in_progress} =
             Installation.begin_setup(
               token,
               "Other Institution",
               "https://gradepush.example",
               other_nonce
             )

    assert {:error, :invalid_setup_state} =
             Installation.convert_manifest(state, "code", other_nonce)

    expired_at = DateTime.add(DateTime.utc_now(), -1, :second)
    Repo.update!(Ecto.Changeset.change(credential, state_expires_at: expired_at))

    assert {:ok, %{state: replacement_state}} =
             Installation.begin_setup(
               token,
               "Test Institution",
               "https://gradepush.example",
               other_nonce
             )

    refute replacement_state == state
  end

  test "only an active organization owner can connect its GitHub installation" do
    %{user: teacher} = configured_gradepush_fixture()

    assert {:ok,
            %{
              id: 123,
              account: %{id: 789, login: "gradepush-test", type: "Organization"}
            }} = Installation.verify_user_installation(teacher, 123)

    Fake.set_organization_membership("gradepush-test", %{"state" => "active", "role" => "member"})

    assert {:error, :organization_owner_required} =
             Installation.verify_user_installation(teacher, 123)

    Fake.set_organization_membership("gradepush-test", %{"state" => "pending", "role" => "admin"})

    assert {:error, :organization_owner_required} =
             Installation.verify_user_installation(teacher, 123)
  end
end
