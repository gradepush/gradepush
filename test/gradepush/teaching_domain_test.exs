defmodule GradePush.TeachingDomainTest do
  use GradePush.DataCase, async: true

  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures

  alias GradePush.{Assignments, Classrooms, Repo, Submissions}
  alias GradePush.Assignments.{AssignmentTest, Repository, Subject}
  alias GradePush.Classrooms.GitHubConnection

  test "duplicate team names return validation errors instead of raising" do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    assignment = assignment_fixture(teacher, classroom, %{kind: "team", team_mode: "teacher"})

    assert {:ok, _team} = Assignments.create_team(teacher, assignment.id, %{name: "Pair A"})

    assert {:error, %Ecto.Changeset{valid?: false, errors: errors}} =
             Assignments.create_team(teacher, assignment.id, %{name: "Pair A"})

    assert Keyword.has_key?(errors, :name)
  end

  test "duplicate student-created team names return a changeset and roll back acceptance" do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    assignment = assignment_fixture(teacher, classroom, %{kind: "team", team_mode: "students"})
    {:ok, invitation} = Assignments.create_assignment_invitation(teacher, assignment.id)
    first_student = user_fixture()
    second_student = user_fixture()

    assert {:ok, _accepted} =
             Assignments.accept_assignment_invitation(first_student, invitation.token, %{
               name: "First student",
               student_id: "S-10",
               team_name: "Shared name"
             })

    assert {:error, %Ecto.Changeset{valid?: false, errors: errors}} =
             Assignments.accept_assignment_invitation(second_student, invitation.token, %{
               name: "Second student",
               student_id: "S-11",
               team_name: "Shared name"
             })

    assert Keyword.has_key?(errors, :name)
    refute GradePush.Accounts.student?(second_student)
  end

  test "same grading rules can be re-submitted after acceptance, but changed rules are locked" do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)

    test_config = %{
      name: "Build",
      description: "Compile the project",
      type: "command",
      command: "mix test",
      points: 10,
      timeout_seconds: 300
    }

    assignment =
      assignment_fixture(teacher, classroom, %{
        autograding_enabled: true,
        tests: [test_config]
      })

    {:ok, invitation} = Assignments.create_assignment_invitation(teacher, assignment.id)
    student = user_fixture()

    assert {:ok, _accepted} =
             Assignments.accept_assignment_invitation(student, invitation.token, %{
               name: "Student One",
               student_id: "S-1"
             })

    [stored_test] =
      Repo.all(from(test in AssignmentTest, where: test.assignment_id == ^assignment.id))

    subject = Repo.one!(from(subject in Subject, where: subject.assignment_id == ^assignment.id))
    repository = Repo.get_by!(Repository, subject_id: subject.id)
    commit_sha = String.duplicate("c", 40)

    assert {:ok, _push} =
             Submissions.record_push(
               assignment.id,
               repository.id,
               commit_sha,
               DateTime.utc_now(),
               "grading-rules-delivery"
             )

    assert {:ok, _grade} =
             Submissions.record_grade(
               assignment.id,
               repository.id,
               grade_attrs(10, commit_sha, stored_test)
             )

    assert {:ok, _updated} =
             Assignments.update_assignment(teacher, assignment.id, %{
               title: "Updated instructions",
               tests: [],
               template_repository: ""
             })

    assert {:ok, _updated} =
             Assignments.update_assignment(teacher, assignment.id, %{tests: [test_config]})

    assert Repo.get_by!(AssignmentTest, assignment_id: assignment.id).id == stored_test.id

    assert {:error, :assignment_locked} =
             Assignments.update_assignment(teacher, assignment.id, %{
               tests: [%{test_config | points: 9}]
             })
  end

  test "a late result for an old commit does not hide the grade for the latest push" do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)

    assignment =
      assignment_fixture(teacher, classroom, %{
        autograding_enabled: true,
        tests: [
          %{
            name: "Build",
            type: "command",
            command: "mix test",
            points: 10,
            timeout_seconds: 300
          }
        ]
      })

    {:ok, invitation} = Assignments.create_assignment_invitation(teacher, assignment.id)
    student = user_fixture()

    {:ok, %{subject: subject}} =
      Assignments.accept_assignment_invitation(student, invitation.token, %{
        name: "Student One",
        student_id: "S-2"
      })

    %Repository{id: repository_id} = Repo.get_by!(Repository, subject_id: subject.id)
    [test] = Repo.all(from(test in AssignmentTest, where: test.assignment_id == ^assignment.id))

    old_sha = String.duplicate("a", 40)
    latest_sha = String.duplicate("b", 40)

    {:ok, _} =
      Submissions.record_push(
        assignment.id,
        repository_id,
        old_sha,
        DateTime.utc_now(),
        "delivery-old"
      )

    {:ok, _} =
      Submissions.record_grade(assignment.id, repository_id, grade_attrs(1, old_sha, test))

    {:ok, _} =
      Submissions.record_push(
        assignment.id,
        repository_id,
        latest_sha,
        DateTime.utc_now(),
        "delivery-latest"
      )

    {:ok, latest_grade} =
      Submissions.record_grade(assignment.id, repository_id, grade_attrs(2, latest_sha, test))

    {:ok, _late_old_grade} =
      Submissions.record_grade(assignment.id, repository_id, grade_attrs(3, old_sha, test))

    assert {:ok, [submission]} = Assignments.list_submissions(teacher, assignment.id)
    assert submission.latest_push.commit_sha == latest_sha
    assert submission.latest_grade.id == latest_grade.id
    assert submission.latest_grade.commit_sha == latest_sha
  end

  test "a later member joining a ready teacher-assigned team re-enqueues repository access" do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)

    assignment =
      assignment_fixture(teacher, classroom, %{
        kind: "team",
        team_mode: "teacher",
        team_size: 2
      })

    first = user_fixture()
    second = user_fixture()
    {:ok, classroom_invitation} = Classrooms.create_class_invitation(teacher, classroom.id)

    for {student, student_id} <- [{first, "S-3"}, {second, "S-4"}] do
      assert {:ok, _} =
               Classrooms.accept_class_invitation(student, classroom_invitation.token, %{
                 name: "Team student",
                 student_id: student_id
               })
    end

    {:ok, team} = Assignments.create_team(teacher, assignment.id, %{name: "Team One"})
    {:ok, _} = Assignments.add_team_member(teacher, assignment.id, team.id, first.id)
    {:ok, _} = Assignments.add_team_member(teacher, assignment.id, team.id, second.id)
    {:ok, invitation} = Assignments.create_assignment_invitation(teacher, assignment.id)

    assert {:ok, %{subject: subject}} =
             Assignments.accept_assignment_invitation(first, invitation.token, %{
               name: "Ignored profile update",
               student_id: "ignored"
             })

    assert subject.team_id == team.id

    assert {:ok, _} =
             Assignments.repository_provisioned(subject.id, %{
               github_repository_id: 20_001,
               owner_login: "gradepush-test",
               name: "team-one",
               full_name: "gradepush-test/team-one",
               html_url: "https://github.com/gradepush-test/team-one"
             })

    from(job in Oban.Job,
      where: job.worker == "GradePush.Workers.ProvisionAssignmentRepository"
    )
    |> Repo.update_all(set: [state: "completed"])

    assert {:ok, %{subject: second_subject}} =
             Assignments.accept_assignment_invitation(second, invitation.token, %{
               name: "Second student",
               student_id: "S-4"
             })

    assert second_subject.id == subject.id

    assert Repo.exists?(
             from(job in Oban.Job,
               where:
                 job.worker == "GradePush.Workers.SyncAssignmentRepositoryAccess" and
                   job.state == "available"
             )
           )
  end

  test "a classroom with assignments cannot change its GitHub organization" do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    assignment_fixture(teacher, classroom)

    another_connection =
      %GitHubConnection{}
      |> GitHubConnection.changeset(%{
        github_organization_id: System.unique_integer([:positive]),
        login: "another-test-org",
        installation_id: System.unique_integer([:positive]),
        sharing_scope: "private",
        status: "active",
        connected_by_id: teacher.id
      })
      |> Repo.insert!()

    assert {:error, :organization_locked} =
             Classrooms.update_classroom(teacher, classroom.id, %{
               github_connection_id: another_connection.id
             })
  end

  test "opening an invitation dialog reuses its active classroom and assignment links" do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    assignment = assignment_fixture(teacher, classroom)

    assert {:ok, class_link} = Classrooms.create_class_invitation(teacher, classroom.id)
    assert {:ok, reopened_class_link} = Classrooms.create_class_invitation(teacher, classroom.id)
    assert reopened_class_link.invitation.id == class_link.invitation.id
    assert reopened_class_link.token == class_link.token
    assert {:ok, _} = Classrooms.classroom_invitation(reopened_class_link.token)

    assert {:ok, assignment_link} =
             Assignments.create_assignment_invitation(teacher, assignment.id)

    assert {:ok, reopened_assignment_link} =
             Assignments.create_assignment_invitation(teacher, assignment.id)

    assert reopened_assignment_link.invitation.id == assignment_link.invitation.id
    assert reopened_assignment_link.token == assignment_link.token
    assert {:ok, _} = Assignments.assignment_invitation(reopened_assignment_link.token)
  end

  defp grade_attrs(run_id, commit_sha, test) do
    %{
      run_id: run_id,
      commit_sha: commit_sha,
      status: "success",
      score: 10,
      max_score: 10,
      tests: [
        %{
          test_id: test.id,
          name: test.name,
          status: "success",
          points_awarded: 10,
          max_points: 10
        }
      ]
    }
  end
end
