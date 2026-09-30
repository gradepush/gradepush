defmodule GradePush.SubmissionActivityTest do
  use GradePush.DataCase, async: true, group: :institution

  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures
  alias GradePush.{Assignments, Repo, Submissions, Time}
  alias GradePush.Assignments.Repository
  alias GradePush.Submissions.Push

  test "daily activity counts every recent push and excludes older history" do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    assignment = assignment_fixture(teacher, classroom)
    student = user_fixture()
    {:ok, invite} = Assignments.create_assignment_invitation(teacher, assignment.id)

    {:ok, %{subject: subject}} =
      Assignments.accept_assignment_invitation(student, invite.token, %{
        name: "Camille",
        student_id: "student-1"
      })

    repository = Repo.get_by!(Repository, subject_id: subject.id)
    now = DateTime.utc_now()

    rows =
      for index <- 1..76 do
        %{
          subject_id: subject.id,
          repository_id: repository.id,
          commit_sha: String.duplicate("a", 40),
          observed_at: if(index == 76, do: DateTime.add(now, -15, :day), else: now),
          delivery_id: "activity-#{subject.id}-#{index}",
          inserted_at: now
        }
      end

    Repo.insert_all(Push, rows)

    assert {:ok, activity} = Submissions.list_assignment_activity(teacher, assignment.id)
    expected_date = now |> DateTime.shift_zone!(Time.timezone()) |> DateTime.to_date()
    assert [%{date: ^expected_date, count: 75}] = activity[subject.id]

    midnight =
      expected_date
      |> Date.add(-2)
      |> DateTime.new!(~T[00:00:00.000000], Time.timezone())
      |> DateTime.shift_zone!("Etc/UTC")

    for seconds <- [-60, 60] do
      Repo.insert!(%Push{
        subject_id: subject.id,
        repository_id: repository.id,
        commit_sha: String.duplicate("b", 40),
        observed_at: DateTime.add(midnight, seconds),
        delivery_id: "midnight-#{subject.id}-#{seconds}"
      })
    end

    assert {:ok, activity} = Submissions.list_assignment_activity(teacher, assignment.id)

    assert Map.new(activity[subject.id], &{&1.date, &1.count}) == %{
             expected_date => 75,
             Date.add(expected_date, -2) => 1,
             Date.add(expected_date, -3) => 1
           }

    assert {:error, :not_found} =
             Submissions.list_assignment_activity(user_fixture(), assignment.id)
  end
end
