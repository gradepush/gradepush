defmodule GradePush.SubmissionsEnrichmentTest do
  use GradePush.DataCase, async: true, group: :institution

  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures

  alias GradePush.{Assignments, Submissions}
  alias GradePush.Assignments.Repository
  alias GradePush.Submissions.{Grade, Push}

  test "enriches each subject with its newest push and a grade for that commit" do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    assignment = assignment_fixture(teacher, classroom)
    student = user_fixture()
    ungraded_student = user_fixture()
    empty_student = user_fixture()
    {:ok, invitation} = Assignments.create_assignment_invitation(teacher, assignment.id)

    {:ok, %{subject: subject}} =
      Assignments.accept_assignment_invitation(student, invitation.token, %{
        name: "Camille",
        student_id: "student-1"
      })

    {:ok, %{subject: empty_subject}} =
      Assignments.accept_assignment_invitation(empty_student, invitation.token, %{
        name: "Riley",
        student_id: "student-3"
      })

    repository = GradePush.Repo.get_by!(Repository, subject_id: subject.id)

    {:ok, %{subject: ungraded_subject}} =
      Assignments.accept_assignment_invitation(ungraded_student, invitation.token, %{
        name: "Morgan",
        student_id: "student-2"
      })

    ungraded_repository = GradePush.Repo.get_by!(Repository, subject_id: ungraded_subject.id)
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    previous_time = DateTime.add(now, -1, :second)
    old_sha = String.duplicate("a", 40)
    tied_sha = String.duplicate("b", 40)
    newest_sha = String.duplicate("c", 40)

    insert_push(subject, repository, old_sha, previous_time, "old")
    insert_push(subject, repository, tied_sha, now, "tie-first")
    newest_push = insert_push(subject, repository, newest_sha, now, "tie-second")

    insert_grade(subject, repository, tied_sha, 1, DateTime.add(now, 100, :second), 9)
    insert_grade(subject, repository, newest_sha, 2, previous_time, 6)
    insert_grade(subject, repository, newest_sha, 3, now, 8)
    newest_grade = insert_grade(subject, repository, newest_sha, 4, now, 10)
    ungraded_sha = String.duplicate("d", 40)

    ungraded_push =
      insert_push(ungraded_subject, ungraded_repository, ungraded_sha, now, "ungraded")

    [enriched, ungraded, empty] =
      Submissions.enrich_subjects([subject, ungraded_subject, empty_subject])

    assert enriched.latest_push.id == newest_push.id
    assert enriched.latest_push.commit_sha == newest_sha
    assert enriched.latest_grade.id == newest_grade.id
    assert Decimal.equal?(enriched.latest_grade.score, Decimal.new(10))
    assert ungraded.latest_push.id == ungraded_push.id
    assert is_nil(ungraded.latest_grade)
    assert is_nil(empty.latest_push)
    assert is_nil(empty.latest_grade)
  end

  defp insert_push(subject, repository, sha, observed_at, suffix) do
    %Push{}
    |> Push.changeset(%{
      subject_id: subject.id,
      repository_id: repository.id,
      commit_sha: sha,
      branch: "main",
      observed_at: observed_at,
      delivery_id: "enrichment-#{subject.id}-#{suffix}"
    })
    |> GradePush.Repo.insert!()
  end

  defp insert_grade(subject, repository, sha, run_id, inserted_at, score) do
    %Grade{inserted_at: inserted_at}
    |> Grade.changeset(%{
      subject_id: subject.id,
      repository_id: repository.id,
      commit_sha: sha,
      run_id: run_id,
      status: "success",
      score: score,
      max_score: 10
    })
    |> GradePush.Repo.insert!()
  end
end
