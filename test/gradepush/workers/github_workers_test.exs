defmodule GradePush.Workers.GitHubWorkersTest do
  use GradePush.DataCase, async: false

  import Ecto.Query
  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures

  alias GradePush.Assignments
  alias GradePush.Assignments.Repository
  alias GradePush.Classrooms.GitHubConnection
  alias GradePush.Crypto
  alias GradePush.GitHub.Delivery
  alias GradePush.GitHub.Fake
  alias GradePush.GitHub.Webhooks
  alias GradePush.Installation.GitHubApp
  alias GradePush.Repo
  alias GradePush.Submissions
  alias GradePush.Submissions.{Grade, Push}

  alias GradePush.Workers.{
    ProcessGitHubDelivery,
    ProvisionAssignmentRepository,
    SyncAssignmentRepositoryAccess
  }

  setup do
    previous = Application.get_env(:gradepush, GradePush.GitHub, [])
    Application.put_env(:gradepush, GradePush.GitHub, Keyword.put(previous, :adapter, Fake))
    Fake.reset!()

    on_exit(fn ->
      Application.put_env(:gradepush, GradePush.GitHub, previous)
      Fake.reset!()
    end)

    :ok
  end

  test "provisions idempotently and resolves the recipient's current login from their stable ID" do
    insert_app()
    %{subject: subject, student: student} = accepted_subject()

    assert :ok = provision(subject.id)
    repository = Repo.get_by!(Repository, subject_id: subject.id)
    assert repository.state == "ready"
    assert repository.github_repository_id

    assert Fake.collaborators(repository.owner_login, repository.name) == [
             "student-#{student.github_id}"
           ]

    refute Fake.collaborators(repository.owner_login, repository.name)
           |> Enum.member?(student.login)

    assert :ok = provision(subject.id)
    retried = Repo.get_by!(Repository, subject_id: subject.id)
    assert retried.github_repository_id == repository.github_repository_id

    assert Fake.collaborators(repository.owner_login, repository.name) == [
             "student-#{student.github_id}"
           ]
  end

  test "a partial remote setup failure resumes from the persisted repository identity" do
    insert_app()

    %{subject: subject} =
      accepted_subject(
        autograding_enabled: true,
        tests: [%{name: "Smoke test", type: "command", command: "true", points: 2}]
      )

    Fake.fail_next(:install_autograding_workflow, :temporary_github_failure)

    assert {:error, :temporary_github_failure} = provision(subject.id)
    pending = Repo.get_by!(Repository, subject_id: subject.id)
    assert pending.state == "pending"
    assert pending.github_repository_id

    assert :ok = provision(subject.id)
    ready = Repo.get_by!(Repository, subject_id: subject.id)
    assert ready.state == "ready"
    assert ready.github_repository_id == pending.github_repository_id
    assert ready.workflow_id == 1122
    assert ready.workflow_path == ".github/workflows/gradepush.yml"
    assert ready.workflow_file_sha == "test-workflow-file-sha"
  end

  test "push deliveries record server-observed time once, and workflow results reject changed definitions" do
    insert_app()

    %{subject: subject} =
      accepted_subject(
        autograding_enabled: true,
        tests: [%{name: "Smoke test", type: "command", command: "true", points: 2}]
      )

    assert :ok = provision(subject.id)
    repository = Repo.get_by!(Repository, subject_id: subject.id)
    commit_sha = String.duplicate("a", 40)
    observed_at = ~U[2026-09-27 15:04:05.000000Z]

    Fake.set_workflow_run(repository.owner_login, repository.name, 900, 1, %{
      "actor" => %{"type" => "Bot", "login" => "gradepush-test[bot]"}
    })

    setup_run =
      insert_delivery(
        "workflow_run",
        "setup-run",
        workflow_payload(repository, 900, commit_sha),
        observed_at
      )

    assert :ok = process_delivery(setup_run)
    assert Repo.get!(Delivery, setup_run.id).status == "ignored"
    refute Repo.get_by(Grade, repository_id: repository.id, run_id: 900)

    push_delivery =
      insert_delivery(
        "push",
        "push-1",
        %{
          "repository_id" => repository.github_repository_id,
          "commit_sha" => commit_sha,
          "branch" => "main"
        },
        observed_at
      )

    assert :ok = process_delivery(push_delivery)

    assert %Push{observed_at: ^observed_at, commit_sha: ^commit_sha} =
             Repo.get_by!(Push, delivery_id: "push-1")

    assert :ok = process_delivery(push_delivery)
    assert Repo.aggregate(from(push in Push, where: push.delivery_id == "push-1"), :count) == 1

    passing_run =
      insert_delivery(
        "workflow_run",
        "run-1",
        workflow_payload(repository, 901, commit_sha),
        observed_at
      )

    assert :ok = process_delivery(passing_run)
    assert %Delivery{status: "processed"} = Repo.get!(Delivery, passing_run.id)

    assert %Grade{status: "success", score: score, max_score: max_score} =
             Repo.get_by!(Grade, repository_id: repository.id, run_id: 901)

    assert Decimal.equal?(score, Decimal.new(2))
    assert Decimal.equal?(max_score, Decimal.new(2))

    Fake.set_workflow_file_sha(repository.owner_login, repository.name, "changed-workflow-blob")

    modified_run =
      insert_delivery(
        "workflow_run",
        "run-2",
        workflow_payload(repository, 902, commit_sha),
        observed_at
      )

    assert :ok = process_delivery(modified_run)

    assert %Grade{
             status: "untrusted",
             score: score,
             max_score: max_score,
             reason: "workflow_modified"
           } =
             Repo.get_by!(Grade, repository_id: repository.id, run_id: 902)

    assert Decimal.equal?(score, Decimal.new(0))
    assert Decimal.equal?(max_score, Decimal.new(0))
  end

  test "exhausted setup jobs mark the repository failed with a sanitized error" do
    %{subject: subject} = accepted_subject()
    Repo.delete_all(GitHubApp)

    assert {:discard, "github_unavailable"} =
             provision(subject.id, attempt: 10, max_attempts: 10)

    assert %Repository{state: "failed", last_error: "github_unavailable"} =
             Repo.get_by!(Repository, subject_id: subject.id)
  end

  test "a workflow received before its push is retried and recovered even after exhausted attempts" do
    %{subject: subject} =
      accepted_subject(
        autograding_enabled: true,
        tests: [%{name: "Smoke", type: "command", command: "true", points: 2}]
      )

    assert :ok = provision(subject.id)
    repository = Repo.get_by!(Repository, subject_id: subject.id)
    sha = String.duplicate("a", 40)
    observed_at = ~U[2026-09-27 15:04:05.000000Z]

    run =
      insert_delivery(
        "workflow_run",
        "out-of-order",
        workflow_payload(repository, 950, sha),
        observed_at
      )

    assert {:error, "push_not_recorded"} = process_delivery(run)
    assert Repo.get!(Delivery, run.id).status == "pending"

    assert {:discard, "push_not_recorded"} =
             ProcessGitHubDelivery.perform(%Oban.Job{
               args: %{"delivery_id" => run.id},
               attempt: 10,
               max_attempts: 10
             })

    assert {:ok, 0} = Webhooks.reconcile_grading()

    push =
      insert_delivery(
        "push",
        "late-push",
        %{
          "repository_id" => repository.github_repository_id,
          "commit_sha" => sha,
          "branch" => "main"
        },
        observed_at
      )

    assert :ok = process_delivery(push)
    assert {:ok, 1} = Webhooks.reconcile_grading()
    assert {:ok, 0} = Webhooks.reconcile_grading()
    assert :ok = process_delivery(Repo.get!(Delivery, run.id))
    assert Repo.get!(Delivery, run.id).status == "processed"
    assert Repo.get_by!(Grade, repository_id: repository.id, run_id: 950).status == "success"
    assert Repo.get_by!(Push, delivery_id: "late-push").observed_at == observed_at
  end

  test "reruns preserve attempts and older deliveries cannot replace the latest result" do
    %{subject: subject} =
      accepted_subject(
        autograding_enabled: true,
        tests: [%{name: "Smoke", type: "command", command: "true", points: 2}]
      )

    assert :ok = provision(subject.id)
    repository = Repo.get_by!(Repository, subject_id: subject.id)
    sha = String.duplicate("a", 40)
    now = DateTime.utc_now()

    push =
      insert_delivery(
        "push",
        "rerun-push",
        %{
          "repository_id" => repository.github_repository_id,
          "commit_sha" => sha,
          "branch" => "main"
        },
        now
      )

    assert :ok = process_delivery(push)

    for {attempt, conclusion} <- [{2, "success"}, {1, "failure"}, {2, "success"}, {3, "failure"}] do
      Fake.set_workflow_run(repository.owner_login, repository.name, 951, attempt, %{
        "conclusion" => conclusion
      })

      payload = Map.put(workflow_payload(repository, 951, sha), "run_attempt", attempt)

      run =
        insert_delivery(
          "workflow_run",
          "rerun-#{System.unique_integer([:positive])}",
          payload,
          now
        )

      assert :ok = process_delivery(run)
      [enriched] = Submissions.enrich_subjects([subject])
      assert enriched.latest_grade.run_attempt == max(2, attempt)
      assert enriched.latest_grade.status == if(attempt == 3, do: "failure", else: "success")
    end

    assert Repo.aggregate(from(g in Grade, where: g.repository_id == ^repository.id), :count) == 3

    assert Repo.get_by!(Grade, repository_id: repository.id, run_id: 951, run_attempt: 1).status ==
             "failure"

    assert Repo.get_by!(Grade, repository_id: repository.id, run_id: 951, run_attempt: 2).status ==
             "success"
  end

  test "rerunning only failed jobs carries forward successful jobs from an earlier attempt" do
    %{subject: subject} =
      accepted_subject(
        autograding_enabled: true,
        tests: [
          %{name: "First", type: "command", command: "true", points: 2},
          %{name: "Second", type: "command", command: "true", points: 3}
        ]
      )

    assert :ok = provision(subject.id)
    repository = Repo.get_by!(Repository, subject_id: subject.id)
    {:ok, target} = Submissions.workflow_target(repository.github_repository_id)
    [first, second] = target.tests

    job = fn definition, conclusion ->
      %{
        "name" => "GradePush test [gp-test-#{definition.id}] #{definition.name}",
        "conclusion" => conclusion
      }
    end

    Fake.set_workflow_jobs(repository.owner_login, repository.name, 952, 1, [
      job.(first, "success"),
      job.(second, "failure")
    ])

    Fake.set_workflow_jobs(repository.owner_login, repository.name, 952, 2, [
      job.(second, "success")
    ])

    sha = String.duplicate("a", 40)
    now = DateTime.utc_now()

    assert :ok =
             process_delivery(
               insert_delivery(
                 "push",
                 "partial-rerun-push",
                 %{
                   "repository_id" => repository.github_repository_id,
                   "commit_sha" => sha,
                   "branch" => "main"
                 },
                 now
               )
             )

    run =
      insert_delivery(
        "workflow_run",
        "partial-rerun",
        Map.put(workflow_payload(repository, 952, sha), "run_attempt", 2),
        now
      )

    assert :ok = process_delivery(run)
    grade = Repo.get_by!(Grade, repository_id: repository.id, run_id: 952, run_attempt: 2)
    assert Decimal.equal?(grade.score, Decimal.new(5))
    assert length(Repo.preload(grade, :tests).tests) == 2
  end

  test "setup bot pushes are ignored while other bot pushes remain recorded" do
    insert_app()
    %{subject: subject} = accepted_subject()
    assert :ok = provision(subject.id)
    repository = Repo.get_by!(Repository, subject_id: subject.id)
    observed_at = ~U[2026-09-27 15:04:05.000000Z]

    own_setup_push =
      insert_delivery(
        "push",
        "setup-bot-push",
        push_payload(repository, String.duplicate("b", 40), "gradepush-test[bot]"),
        observed_at
      )

    assert :ok = process_delivery(own_setup_push)
    assert Repo.get!(Delivery, own_setup_push.id).status == "ignored"

    assert Repo.aggregate(from(push in Push, where: push.repository_id == ^repository.id), :count) ==
             0

    other_bot_push =
      insert_delivery(
        "push",
        "other-bot-push",
        push_payload(repository, String.duplicate("c", 40), "renovate[bot]"),
        observed_at
      )

    assert :ok = process_delivery(other_bot_push)
    assert Repo.get!(Delivery, other_bot_push.id).status == "processed"

    assert Repo.aggregate(from(push in Push, where: push.repository_id == ^repository.id), :count) ==
             1
  end

  test "a terminal collaborator sync failure is visible and safely retryable" do
    insert_app()
    %{subject: subject} = accepted_subject()
    assert :ok = provision(subject.id)
    Fake.fail_next(:add_collaborator, :forbidden)

    assert {:discard, "collaborator_setup_failed"} =
             SyncAssignmentRepositoryAccess.perform(%Oban.Job{
               args: %{"subject_id" => subject.id},
               attempt: 1,
               max_attempts: 10
             })

    assert %Repository{state: "ready", access_sync_state: "failed"} =
             Repo.get_by!(Repository, subject_id: subject.id)
  end

  defp accepted_subject(assignment_attrs \\ []) do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    connection = Repo.get!(GitHubConnection, classroom.github_connection_id)

    connection
    |> GitHubConnection.changeset(%{
      github_organization_id: 789,
      login: "gradepush-test",
      installation_id: 123
    })
    |> Repo.update!()

    assignment = assignment_fixture(teacher, classroom, Map.new(assignment_attrs))
    github_id = 800_000 + System.unique_integer([:positive, :monotonic])
    student = user_fixture(%{github_id: github_id, login: "stale-handle-#{github_id}"})
    {:ok, invitation} = Assignments.create_assignment_invitation(teacher, assignment.id)

    {:ok, %{subject: subject}} =
      Assignments.accept_assignment_invitation(student, invitation.token, %{
        name: "Test Student",
        student_id: "ST-#{github_id}"
      })

    %{subject: subject, student: student}
  end

  defp insert_app do
    {:ok, client_secret} = Crypto.encrypt("test-client-secret", "github_app.client_secret")
    {:ok, private_key} = Crypto.encrypt("test-private-key", "github_app.private_key")
    {:ok, webhook_secret} = Crypto.encrypt("test-webhook-secret", "github_app.webhook_secret")

    %GitHubApp{}
    |> GitHubApp.changeset(%{
      app_id: 456,
      client_id: "test-client-id",
      client_secret_encrypted: client_secret,
      private_key_encrypted: private_key,
      webhook_secret_encrypted: webhook_secret,
      slug: "gradepush-test",
      html_url: "https://github.com/apps/gradepush-test"
    })
    |> Repo.insert!()
  end

  defp provision(subject_id, options \\ []) do
    ProvisionAssignmentRepository.perform(%Oban.Job{
      args: %{"subject_id" => subject_id},
      attempt: Keyword.get(options, :attempt, 1),
      max_attempts: Keyword.get(options, :max_attempts, 10)
    })
  end

  defp insert_delivery(event, delivery_id, payload, received_at) do
    %Delivery{}
    |> Delivery.changeset(%{
      delivery_id: delivery_id,
      event: event,
      action: if(event == "workflow_run", do: "completed", else: nil),
      payload_sha256: :crypto.hash(:sha256, Jason.encode!(payload)),
      payload: payload,
      status: "pending",
      received_at: received_at
    })
    |> Repo.insert!()
  end

  defp push_payload(repository, commit_sha, sender_login) do
    %{
      "repository_id" => repository.github_repository_id,
      "commit_sha" => commit_sha,
      "branch" => "main",
      "sender_type" => "Bot",
      "sender_login" => sender_login
    }
  end

  defp process_delivery(delivery) do
    ProcessGitHubDelivery.perform(%Oban.Job{
      args: %{"delivery_id" => delivery.id},
      attempt: 1,
      max_attempts: 10
    })
  end

  defp workflow_payload(repository, run_id, commit_sha) do
    %{
      "repository_id" => repository.github_repository_id,
      "repository_name" => repository.name,
      "owner_login" => repository.owner_login,
      "run_id" => run_id,
      "workflow_id" => 1122,
      "commit_sha" => commit_sha,
      "event" => "push",
      "status" => "completed",
      "conclusion" => "success"
    }
  end
end
