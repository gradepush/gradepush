defmodule GradePush.CLITest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias GradePush.Accounts
  alias GradePush.Accounts.{InstitutionMembership, User}
  alias GradePush.Assignments.{Assignment, Repository, Subject, Team, TeamMember}
  alias GradePush.Classrooms.Classroom
  alias GradePush.CLI
  alias GradePush.CLI.{AccessToken, DeviceAuthorization}
  alias GradePush.Crypto
  alias GradePush.Repo

  setup do
    sandbox_owner = Sandbox.start_owner!(Repo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(sandbox_owner) end)

    previous_demo = Application.get_env(:gradepush, :demo_mode, false)
    Application.put_env(:gradepush, :demo_mode, false)

    on_exit(fn -> Application.put_env(:gradepush, :demo_mode, previous_demo) end)
    {:ok, sandbox_owner: sandbox_owner}
  end

  test "device authorization stores hashes, approves once, issues a separate token, and revokes it" do
    teacher = teacher_fixture()
    student = student_fixture()

    assert {:ok, request} = CLI.request_device("cli-test-#{System.unique_integer([:positive])}")
    assert request.expires_in == 600
    assert request.interval == 5
    assert request.user_code =~ ~r/\A[A-HJ-NP-Z2-9]{5}-[A-HJ-NP-Z2-9]{5}\z/

    authorization =
      Repo.get_by!(DeviceAuthorization,
        device_code_hash: Crypto.hash(request.device_code)
      )

    assert authorization.user_code_hash == Crypto.hash(String.replace(request.user_code, "-", ""))
    refute authorization.device_code_hash == request.device_code
    refute authorization.user_code_hash == request.user_code
    assert authorization.status == "pending"

    assert {:error, :unauthorized} = CLI.approve(student, request.user_code)
    assert {:error, :invalid_user_code} = CLI.approve(teacher, [request.user_code])
    assert {:error, :invalid_user_code} = CLI.deny(teacher, %{})

    update_device(authorization, inserted_at: ago(10))
    assert {:error, :authorization_pending} = CLI.poll_device(request.device_code)

    assert :ok = CLI.approve(teacher, String.downcase(request.user_code))
    assert {:error, :request_already_handled} = CLI.approve(teacher, request.user_code)

    update_device(authorization, last_polled_at: ago(10))
    assert {:ok, token_response} = CLI.poll_device(request.device_code)
    assert token_response.token_type == "Bearer"
    assert token_response.expires_in == 7_776_000

    token = Repo.get_by!(AccessToken, token_hash: Crypto.hash(token_response.access_token))
    assert token.user_id == teacher.id
    refute token.token_hash == token_response.access_token
    assert CLI.authenticate_access_token(token_response.access_token).login == teacher.login

    assert {:error, :invalid_grant} = CLI.poll_device(request.device_code)
    assert :ok = CLI.revoke_access_token(token_response.access_token)
    assert is_nil(CLI.authenticate_access_token(token_response.access_token))
    assert Repo.get!(AccessToken, token.id).revoked_at
  end

  test "polling backs off, expires requests, and respects a denial" do
    teacher = teacher_fixture()

    assert {:ok, early} = CLI.request_device("early-#{System.unique_integer([:positive])}")
    assert {:error, :slow_down} = CLI.poll_device(early.device_code)

    early_authorization =
      Repo.get_by!(DeviceAuthorization, device_code_hash: Crypto.hash(early.device_code))

    assert early_authorization.poll_interval_seconds == 10

    assert {:ok, denied} = CLI.request_device("denied-#{System.unique_integer([:positive])}")
    assert :ok = CLI.deny(teacher, denied.user_code)
    assert {:error, :access_denied} = CLI.poll_device(denied.device_code)

    assert {:ok, expired} = CLI.request_device("expired-#{System.unique_integer([:positive])}")

    authorization =
      Repo.get_by!(DeviceAuthorization,
        device_code_hash: Crypto.hash(expired.device_code)
      )

    update_device(authorization, expires_at: ago(1))
    assert {:error, :expired_token} = CLI.poll_device(expired.device_code)
    assert {:error, :expired_request} = CLI.approve(teacher, expired.user_code)
    assert {:error, :invalid_grant} = CLI.poll_device("malformed")
  end

  test "only current teachers can poll approved devices or use CLI tokens" do
    teacher = teacher_fixture()
    assert {:ok, request} = CLI.request_device("role-loss-#{System.unique_integer([:positive])}")
    assert :ok = CLI.approve(teacher, request.user_code)
    update_device_by_code(request.device_code, inserted_at: ago(10))
    assert {:ok, token_response} = CLI.poll_device(request.device_code)

    assert {:ok, pending_role_loss} =
             CLI.request_device("pending-role-loss-#{System.unique_integer([:positive])}")

    assert :ok = CLI.approve(teacher, pending_role_loss.user_code)
    update_device_by_code(pending_role_loss.device_code, inserted_at: ago(10))

    membership =
      Repo.get_by!(InstitutionMembership,
        user_id: teacher.id,
        role: :teacher
      )

    Repo.delete!(membership)

    assert {:error, :access_denied} = CLI.poll_device(pending_role_loss.device_code)
    assert is_nil(CLI.authenticate_access_token(token_response.access_token))

    revoked = Repo.get_by!(AccessToken, token_hash: Crypto.hash(token_response.access_token))
    assert revoked.revoked_at
    refute Accounts.teacher?(teacher)
  end

  test "removing and later restoring teacher access does not revive tokens or approved requests" do
    teacher = teacher_fixture()
    admin = admin_fixture()
    assert {:ok, request} = CLI.request_device("removed-#{System.unique_integer([:positive])}")
    assert :ok = CLI.approve(teacher, request.user_code)
    update_device_by_code(request.device_code, inserted_at: ago(10))
    assert {:ok, token_response} = CLI.poll_device(request.device_code)

    assert {:ok, pending_request} =
             CLI.request_device("removed-pending-#{System.unique_integer([:positive])}")

    assert :ok = CLI.approve(teacher, pending_request.user_code)

    assert {:ok, :ok} = Accounts.remove_teacher(admin, teacher.id)
    token_record = Repo.get_by!(AccessToken, token_hash: Crypto.hash(token_response.access_token))
    assert token_record.revoked_at

    assert {:ok, %{token: invitation}} = Accounts.create_teacher_invitation(admin)
    assert {:ok, _membership} = Accounts.accept_teacher_invitation(teacher, invitation)
    assert Accounts.teacher?(teacher)
    assert is_nil(CLI.authenticate_access_token(token_response.access_token))
    update_device_by_code(pending_request.device_code, inserted_at: ago(10))
    assert {:error, :access_denied} = CLI.poll_device(pending_request.device_code)
  end

  test "device consumption is single-use under concurrent polls", %{sandbox_owner: sandbox_owner} do
    teacher = teacher_fixture()
    assert {:ok, request} = CLI.request_device("race-#{System.unique_integer([:positive])}")
    assert :ok = CLI.approve(teacher, request.user_code)
    update_device_by_code(request.device_code, inserted_at: ago(10))
    parent = self()

    tasks =
      for index <- 1..2 do
        task =
          Task.async(fn ->
            send(parent, {:poll_ready, self()})
            receive do: (:start_poll -> CLI.poll_device(request.device_code, "race-#{index}"))
          end)

        task
      end

    ready_pids = for _ <- tasks, do: receive_ready()
    Enum.each(ready_pids, fn pid -> assert :ok = Sandbox.allow(Repo, sandbox_owner, pid) end)
    Enum.each(ready_pids, &send(&1, :start_poll))

    results = Enum.map(tasks, &Task.await(&1, 5_000))

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :invalid_grant})) == 1
  end

  test "repository manifests are teacher-scoped, paged, deduplicated, and readiness-filtered" do
    teacher = teacher_fixture()
    class = classroom_fixture(teacher, %{title: "CLI Classroom", code: "CLI-1"})
    assignment = assignment_fixture(teacher, class, %{title: "Repository manifest"})
    seed_manifest_repositories(assignment, 101)
    seed_team_repository(teacher, assignment)
    seed_pending_repository(assignment)

    assert {:ok, first_page} = CLI.list_repositories(teacher, class.slug)
    assert first_page.schema_version == 1
    assert first_page.classroom.slug == class.slug
    assert length(first_page.repositories) == 100
    assert first_page.next_page == 2
    assert Enum.all?(first_page.repositories, &(&1.assignment == assignment.slug))
    refute Enum.any?(first_page.repositories, &String.contains?(&1.full_name, "pending"))

    assert {:ok, second_page} = CLI.list_repositories(teacher, class.slug, page: 2)
    assert length(second_page.repositories) == 2
    assert second_page.next_page == nil

    assert Enum.count(
             first_page.repositories ++ second_page.repositories,
             &(&1.full_name == "gradepush-test/shared-team")
           ) == 1

    Repo.update_all(
      from(classroom in Classroom, where: classroom.id == ^class.id),
      set: [slug: "cli_classroom_"]
    )

    Repo.update_all(
      from(record in Assignment, where: record.id == ^assignment.id),
      set: [slug: "public_repository_hiv_"]
    )

    assert {:ok, underscore_manifest} =
             CLI.list_repositories(teacher, "cli_classroom_",
               assignment: "public_repository_hiv_"
             )

    assert underscore_manifest.classroom.slug == "cli_classroom_"

    assert Enum.all?(
             underscore_manifest.repositories,
             &(&1.assignment == "public_repository_hiv_")
           )

    other_teacher = teacher_fixture()
    other_class = classroom_fixture(other_teacher)
    assert {:error, :not_found} = CLI.list_repositories(teacher, other_class.slug)
    assert {:error, :not_found} = CLI.list_repositories(other_teacher, "cli_classroom_")

    assert {:error, :invalid_request} =
             CLI.list_repositories(teacher, "cli_classroom_", page: "2")
  end

  test "demo mode blocks issuance, polling, authentication, and approvals" do
    teacher = teacher_fixture()

    assert {:ok, request} =
             CLI.request_device("before-demo-#{System.unique_integer([:positive])}")

    Application.put_env(:gradepush, :demo_mode, true)
    on_exit(fn -> Application.put_env(:gradepush, :demo_mode, false) end)

    assert {:error, :unavailable_in_demo} = CLI.request_device("demo")
    assert {:error, :unavailable_in_demo} = CLI.poll_device(request.device_code)
    assert {:error, :unavailable_in_demo} = CLI.approve(teacher, request.user_code)
    assert is_nil(CLI.authenticate_access_token("not-a-token"))
  end

  defp teacher_fixture do
    teacher = user_fixture(%{login: "teacher-#{System.unique_integer([:positive])}"})
    teacher_membership_fixture(teacher)
    teacher
  end

  defp update_device(%DeviceAuthorization{id: id}, attrs) do
    from(device in DeviceAuthorization, where: device.id == ^id) |> Repo.update_all(set: attrs)
  end

  defp update_device_by_code(device_code, attrs) do
    hash = Crypto.hash(device_code)

    from(device in DeviceAuthorization, where: device.device_code_hash == ^hash)
    |> Repo.update_all(set: attrs)
  end

  defp ago(seconds), do: DateTime.add(DateTime.utc_now(), -seconds, :second)

  defp receive_ready do
    receive do
      {:poll_ready, pid} -> pid
    after
      5_000 -> flunk("polling task did not start")
    end
  end

  defp seed_manifest_repositories(%Assignment{} = assignment, count) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    suffix = System.unique_integer([:positive])

    users =
      for index <- 1..count do
        %{
          github_id: 90_000_000 + suffix * 1_000 + index,
          login: "manifest-#{suffix}-#{index}",
          locale: "en",
          inserted_at: now,
          updated_at: now
        }
      end

    {^count, inserted_users} = Repo.insert_all(User, users, returning: [:id])

    subjects =
      Enum.map(inserted_users, fn user ->
        %{
          assignment_id: assignment.id,
          kind: "individual",
          user_id: user.id,
          accepted_at: now,
          inserted_at: now,
          updated_at: now
        }
      end)

    {^count, inserted_subjects} = Repo.insert_all(Subject, subjects, returning: [:id])

    repositories =
      inserted_subjects
      |> Enum.with_index(1)
      |> Enum.map(fn {subject, index} ->
        %{
          subject_id: subject.id,
          state: "ready",
          full_name:
            "gradepush-test/manifest-#{suffix}-#{String.pad_leading(to_string(index), 3, "0")}",
          inserted_at: now,
          updated_at: now
        }
      end)

    {^count, _} = Repo.insert_all(Repository, repositories)

    :ok
  end

  defp seed_team_repository(teacher, assignment) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    team =
      %Team{}
      |> Team.changeset(%{
        assignment_id: assignment.id,
        created_by_id: teacher.id,
        name: "Shared repository team"
      })
      |> Repo.insert!()

    subject =
      %Subject{}
      |> Subject.changeset(%{
        assignment_id: assignment.id,
        kind: "team",
        team_id: team.id,
        accepted_at: now
      })
      |> Repo.insert!()

    members =
      for index <- 1..2 do
        user =
          user_fixture(%{login: "team-member-#{System.unique_integer([:positive])}-#{index}"})

        %TeamMember{team_id: team.id, assignment_id: assignment.id, user_id: user.id}
        |> Repo.insert!()
      end

    assert length(members) == 2

    %Repository{}
    |> Repository.changeset(%{
      subject_id: subject.id,
      state: "ready",
      full_name: "gradepush-test/shared-team"
    })
    |> Repo.insert!()
  end

  defp seed_pending_repository(assignment) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    user = user_fixture(%{login: "pending-member-#{System.unique_integer([:positive])}"})

    subject =
      %Subject{}
      |> Subject.changeset(%{
        assignment_id: assignment.id,
        kind: "individual",
        user_id: user.id,
        accepted_at: now
      })
      |> Repo.insert!()

    %Repository{}
    |> Repository.changeset(%{
      subject_id: subject.id,
      state: "pending",
      full_name: "gradepush-test/pending"
    })
    |> Repo.insert!()
  end

  defp admin_fixture do
    user = user_fixture(%{login: "admin-#{System.unique_integer([:positive])}"})
    institution = GradePush.Accounts.institution()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %InstitutionMembership{}
    |> InstitutionMembership.changeset(%{
      institution_id: institution.id,
      user_id: user.id,
      role: :admin,
      joined_at: now
    })
    |> Repo.insert!()

    user
  end
end
