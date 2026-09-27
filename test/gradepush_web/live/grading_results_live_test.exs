defmodule GradePushWeb.GradingResultsLiveTest do
  use GradePushWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures

  alias GradePush.{Assignments, Repo, Submissions}
  alias GradePush.Assignments.Repository

  setup do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)

    assignment =
      assignment_fixture(teacher, classroom,
        autograding_enabled: true,
        tests: [
          %{
            name: "Build",
            description: "Compile the program",
            type: "command",
            command: "true",
            points: 25
          },
          %{
            name: "Output",
            description: "Check the greeting",
            type: "io",
            command: "true",
            expected: "Hello",
            points: 75
          }
        ]
      )

    student = student_fixture()
    {:ok, invitation} = Assignments.create_assignment_invitation(teacher, assignment.id)

    {:ok, %{subject: subject}} =
      Assignments.accept_assignment_invitation(student, invitation.token, %{
        name: student.student_name,
        student_id: student.student_id
      })

    repository = Repo.get_by!(Repository, subject_id: subject.id)

    %{
      teacher: teacher,
      classroom: classroom,
      assignment: assignment,
      student: student,
      subject: subject,
      repository: repository
    }
  end

  test "student and teacher results update for the latest push without keeping stale scores", c do
    path = "/classrooms/#{c.classroom.slug}/assignments/#{c.assignment.slug}"
    {:ok, student_view, _} = c.conn |> log_in_user(c.student) |> live("/student" <> path)
    {:ok, teacher_view, _} = build_conn() |> log_in_user(c.teacher) |> live(path)

    assert has_element?(student_view, "#student-test-results", "No results yet")

    for subject_id <- ["invalid", "0", "999999999"] do
      render_click(teacher_view, "open", %{"kind" => "test_results", "subject_id" => subject_id})
      refute has_element?(teacher_view, "#submission-test-results")
    end

    teacher_view |> element("button.cp-results-link") |> render_click()
    assert has_element?(teacher_view, "#submission-test-results", "No results yet")

    first_sha = String.duplicate("a", 40)
    record_push(c, first_sha, "first")

    assert has_element?(
             student_view,
             "#student-test-results",
             "Awaiting results for the latest push."
           )

    record_grade(c, first_sha, 1)

    assert eventually(fn -> has_element?(teacher_view, ".cp-test-score", "25 / 100") end)
    refute has_element?(teacher_view, ".cp-test-score", "25.00")

    for {view, id} <- [
          {student_view, "student-test-results"},
          {teacher_view, "submission-test-results"}
        ] do
      assert eventually(fn -> has_element?(view, "##{id} .cp-grading-total", "25 / 100") end)
      assert has_element?(view, "##{id} .cp-grading-success", "Passed")
      assert has_element?(view, "##{id} .cp-grading-failure", "Failed")
      assert has_element?(view, "##{id} code[title='#{first_sha}']", "aaaaaaa")

      assert has_element?(
               view,
               "##{id} a[href='https://github.com/test-org/student/actions/runs/1']"
             )
    end

    latest_sha = String.duplicate("b", 40)
    record_push(c, latest_sha, "second")

    for view <- [student_view, teacher_view] do
      assert eventually(fn ->
               has_element?(view, ".cp-grading-summary", "Awaiting results for the latest push.")
             end)

      refute has_element?(view, ".cp-grading-success")
      refute has_element?(view, ".cp-grading-total")
    end

    {:ok, _} =
      Submissions.record_untrusted_result(c.assignment.id, c.repository.id, %{
        commit_sha: latest_sha,
        run_id: 2,
        reason: "workflow_modified"
      })

    for view <- [student_view, teacher_view] do
      assert eventually(fn -> has_element?(view, ".cp-grading-warning", "cannot be verified") end)
      assert has_element?(view, ".cp-grading-status", "Not verified")
      refute has_element?(view, ".cp-grading-total")
    end
  end

  test "another student or teacher cannot retrieve a submission's test results", c do
    sha = String.duplicate("c", 40)
    record_push(c, sha, "private")
    record_grade(c, sha, 1)
    path = "/classrooms/#{c.classroom.slug}/assignments/#{c.assignment.slug}"
    stranger = student_fixture()
    {:ok, student_view, _} = c.conn |> log_in_user(stranger) |> live("/student" <> path)
    refute has_element?(student_view, "#student-test-results")

    {:ok, invitation} = Assignments.create_assignment_invitation(c.teacher, c.assignment.id)

    {:ok, _} =
      Assignments.accept_assignment_invitation(stranger, invitation.token, %{
        name: stranger.student_name,
        student_id: stranger.student_id
      })

    {:ok, own_view, _} = build_conn() |> log_in_user(stranger) |> live("/student" <> path)
    assert has_element?(own_view, "#student-test-results", "No results yet")
    refute has_element?(own_view, ".cp-grading-total")
    refute render(own_view) =~ "actions/runs/1"

    colleague = user_fixture()
    teacher_membership_fixture(colleague)
    {:ok, teacher_view, _} = build_conn() |> log_in_user(colleague) |> live(path)

    render_click(teacher_view, "open", %{
      "kind" => "test_results",
      "subject_id" => to_string(c.subject.id)
    })

    refute has_element?(teacher_view, "#submission-test-results")
    refute render(teacher_view) =~ "actions/runs/1"
  end

  defp record_push(c, sha, delivery) do
    assert {:ok, _} =
             Submissions.record_push(
               c.assignment.id,
               c.repository.id,
               sha,
               DateTime.utc_now(),
               delivery
             )
  end

  defp record_grade(c, sha, run_id) do
    tests =
      Enum.map(c.assignment.tests, fn test ->
        passed? = test.name == "Build"

        %{
          test_id: test.id,
          name: test.name,
          status: if(passed?, do: "success", else: "failure"),
          points_awarded: if(passed?, do: test.points, else: 0),
          max_points: test.points
        }
      end)

    assert {:ok, _} =
             Submissions.record_grade(c.assignment.id, c.repository.id, %{
               commit_sha: sha,
               run_id: run_id,
               status: "failure",
               score: 25,
               max_score: 100,
               html_url: "https://github.com/test-org/student/actions/runs/#{run_id}",
               tests: tests
             })
  end
end
