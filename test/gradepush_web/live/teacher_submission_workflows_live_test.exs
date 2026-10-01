defmodule GradePushWeb.TeacherSubmissionWorkflowsLiveTest do
  use GradePushWeb.ConnCase, async: true, group: :institution

  import Phoenix.LiveViewTest
  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures

  alias GradePush.{Assignments, Classrooms, Repo, Submissions}
  alias GradePush.Assignments.{Repository, Subject}

  test "team actions confirm removal, retain archived results and expose access retries", %{
    conn: conn
  } do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    student = student_fixture()
    enroll_student(classroom, teacher, student)
    assignment = assignment_fixture(teacher, classroom, %{kind: "team", team_mode: "teacher"})
    {:ok, team} = Assignments.create_team(teacher, assignment.id, %{name: "Orion"})
    {:ok, _} = Assignments.add_team_member(teacher, assignment.id, team.id, student.id)
    subject = accept_assignment(assignment, teacher, student)
    {:ok, view, _} = conn |> log_in_user(teacher) |> live(assignment_path(classroom, assignment))
    view |> element("button", "Manage teams") |> render_click()
    panel = "#managed-team-#{team.id}"
    view |> element("#{panel} button[phx-value-action=rename]") |> render_click()

    view
    |> form("#{panel} form[phx-submit=rename_team]", team: %{name: "Atlas"})
    |> render_submit()

    assert has_element?(view, "#team-tab-#{team.id}", "Atlas")
    view |> element("#{panel} button[phx-value-action=remove]") |> render_click()
    assert has_element?(view, "[data-ui=team-confirmation]", "Remove Test Student")
    view |> element("[data-ui=team-confirmation] button", "Cancel") |> render_click()
    assert has_element?(view, "#{panel} li", "Test Student")
    view |> element("#{panel} button[phx-value-action=remove]") |> render_click()
    view |> element("[data-ui=team-confirmation] button", "Remove from team") |> render_click()
    refute has_element?(view, "#{panel} li")
    assert has_element?(view, "#{panel} select[name=student_id]")
    view |> element("#{panel} button[phx-value-action=delete]") |> render_click()
    view |> element("[data-ui=team-confirmation] button", "Delete team") |> render_click()
    refute has_element?(view, "[role=tab]")
    view |> element("button", "Done") |> render_click()
    assert has_element?(view, "#submission-team-#{team.id}", "Deleted team")
    assert has_element?(view, "#submission-team-#{team.id}", "Updating GitHub access")
    view |> element("button", "Manage teams") |> render_click()
    Assignments.repository_access_failed(subject.id)
    send(view.pid, :refresh_workspace)
    view |> element("button", "Done") |> render_click()
    assert has_element?(view, "#submission-team-#{team.id}", "Previous access may remain")
    view |> element("button[phx-click=retry_repository_access]") |> render_click()
    assert has_element?(view, "#submission-team-#{team.id}", "Updating GitHub access")
  end

  test "teacher can retry failed repository setup and sees the pending state", %{conn: conn} do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    student = student_fixture()
    enroll_student(classroom, teacher, student)
    assignment = assignment_fixture(teacher, classroom)
    subject = accept_assignment(assignment, teacher, student)

    {:ok, _failed} = Assignments.repository_provisioning_failed(subject.id, "github_unavailable")

    {:ok, view, _html} =
      conn
      |> log_in_user(teacher)
      |> live(assignment_path(classroom, assignment))

    assert has_element?(view, "#submission-#{student.login}", "Check the connection and retry")
    refute render(view) =~ "github_unavailable"

    view
    |> element("#submission-#{student.login} button[phx-click='retry_repository']")
    |> render_click()

    repository = Repo.get_by!(Repository, subject_id: subject.id)
    assert repository.state == "pending"
    assert repository.last_error == nil
    assert has_element?(view, "#submission-#{student.login}", "Repository is being created.")
  end

  test "teacher manages assigned teams and students inherit their assigned team on acceptance", %{
    conn: conn
  } do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    student = student_fixture()
    enroll_student(classroom, teacher, student)

    assignment =
      assignment_fixture(teacher, classroom, %{
        kind: "team",
        team_mode: "teacher",
        team_size: 2
      })

    {:ok, view, _html} =
      conn
      |> log_in_user(teacher)
      |> live(assignment_path(classroom, assignment))

    view |> element("button", "Manage teams") |> render_click()
    view |> form("[data-ui~='team-create-form']", team: %{name: "Blue Team"}) |> render_submit()

    {:ok, [team]} = Assignments.list_teams(teacher, assignment.id)
    assert team.name == "Blue Team"
    assert has_element?(view, "#managed-team-#{team.id}", "Blue Team")
    assert has_element?(view, "#managed-team-#{team.id}", "No students assigned yet.")
    assert has_element?(view, "#submission-team-#{team.id}", "No students assigned yet.")
    refute has_element?(view, "[data-ui=submissions]", "No teams yet")

    view
    |> form("#managed-team-#{team.id} form[phx-submit='add_team_member']", %{
      "student_id" => to_string(student.id)
    })
    |> render_submit()

    {:ok, [team]} = Assignments.list_teams(teacher, assignment.id)
    assert [%{user_id: student_id}] = team.members
    assert student_id == student.id

    assert has_element?(view, "[role='status']", "Student added to the team.")
    view |> element("button", "Done") |> render_click()
    assert has_element?(view, "#submission-team-#{team.id}", "Waiting for acceptance")
    assert has_element?(view, "#submission-team-#{team.id} a", "Test Student")
    refute has_element?(view, "#submission-team-#{team.id} button")

    view
    |> form("#submission-search", query: student.login, status: "not_accepted")
    |> render_change()

    assert has_element?(view, "#submission-team-#{team.id}")
    view |> form("#submission-search", query: "missing team", status: "all") |> render_change()
    assert has_element?(view, "[data-ui=submissions]", "No matching results")
    refute has_element?(view, "#submission-team-#{team.id}")
    view |> form("#submission-search", query: "", status: "no_push") |> render_change()
    refute has_element?(view, "#submission-team-#{team.id}")
    view |> form("#submission-search", query: "", status: "all") |> render_change()

    view |> element("button", "Share assignment") |> render_click()
    refute has_element?(view, "[role='status']", "Student added to the team.")
    view |> element("[data-ui~='modal-heading'] button[phx-click='close']") |> render_click()

    {:ok, invitation} = Assignments.create_assignment_invitation(teacher, assignment.id)

    {:ok, %{subject: subject}} =
      Assignments.accept_assignment_invitation(student, invitation.token, %{
        name: "Test Student",
        student_id: "2026001"
      })

    assert subject.team_id == team.id

    assert eventually(fn ->
             has_element?(view, "#submission-team-#{team.id}", "Repository is being created.")
           end)

    refute has_element?(view, "#submission-team-#{team.id}", "Waiting for acceptance")
    assert view |> element("#submission-team-#{team.id}") |> render() =~ "Blue Team"
    view |> form("#submission-search", query: "", status: "not_accepted") |> render_change()
    refute has_element?(view, "#submission-team-#{team.id}")
  end

  test "teams remain visible in an empty classroom and alongside accepted teams", %{conn: conn} do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    assignment = assignment_fixture(teacher, classroom, %{kind: "team", team_mode: "teacher"})
    {:ok, waiting} = Assignments.create_team(teacher, assignment.id, %{name: "Waiting team"})
    {:ok, accepted} = Assignments.create_team(teacher, assignment.id, %{name: "Accepted team"})
    conn = log_in_user(conn, teacher)
    {:ok, view, _} = live(conn, assignment_path(classroom, assignment))

    assert has_element?(view, "#submission-team-#{waiting.id}", "Waiting for acceptance")
    view |> element("button", "Manage teams") |> render_click()
    assert has_element?(view, "#managed-team-#{waiting.id}", "once they join the classroom")
    refute has_element?(view, "#managed-team-#{waiting.id} form")

    student = student_fixture()
    enroll_student(classroom, teacher, student)
    {:ok, _} = Assignments.add_team_member(teacher, assignment.id, accepted.id, student.id)
    accept_assignment(assignment, teacher, student)
    {:ok, view, _} = live(conn, assignment_path(classroom, assignment))

    assert has_element?(view, "#submission-team-#{waiting.id}", "Waiting for acceptance")
    assert has_element?(view, "#submission-team-#{accepted.id}", "Repository is being created.")
    assert view |> element("#submission-team-#{accepted.id}") |> render() =~ "Accepted team"
    view |> form("#submission-search", query: "", status: "not_accepted") |> render_change()
    assert has_element?(view, "#submission-team-#{waiting.id}")
    refute has_element?(view, "#submission-team-#{accepted.id}")
  end

  test "team tabs select only this assignment's teams and preserve selection on updates", %{
    conn: conn
  } do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    student = student_fixture()
    enroll_student(classroom, teacher, student)
    assignment = assignment_fixture(teacher, classroom, %{kind: "team", team_mode: "teacher"})
    other = assignment_fixture(teacher, classroom, %{kind: "team", team_mode: "teacher"})
    {:ok, first} = Assignments.create_team(teacher, assignment.id, %{name: "First"})
    {:ok, second} = Assignments.create_team(teacher, assignment.id, %{name: "Second"})
    {:ok, foreign} = Assignments.create_team(teacher, other.id, %{name: "Other assignment"})
    {:ok, view, _} = conn |> log_in_user(teacher) |> live(assignment_path(classroom, assignment))
    view |> element("button", "Manage teams") |> render_click()

    assert has_element?(view, "#team-tab-#{first.id}[aria-selected=true][tabindex='0']")
    assert has_element?(view, "#managed-team-#{second.id}[hidden]")
    view |> element("#team-tab-#{second.id}") |> render_click()
    assert has_element?(view, "#team-tab-#{second.id}[aria-selected=true]")
    assert has_element?(view, "#managed-team-#{first.id}[hidden]")
    refute has_element?(view, "#managed-team-#{second.id}[hidden]")

    for value <- [to_string(foreign.id), "invalid"] do
      render_click(view, "select_team", %{"team_id" => value})
      assert has_element?(view, "#team-tab-#{second.id}[aria-selected=true]")
    end

    view
    |> form("#managed-team-#{second.id} form", student_id: to_string(student.id))
    |> render_submit()

    assert has_element?(view, "#team-tab-#{second.id}[aria-selected=true]", "1/2")
    assert has_element?(view, "#managed-team-#{second.id}", "Test Student")

    view |> form("[data-ui=team-create-form]", team: %{name: "Third"}) |> render_submit()
    {:ok, teams} = Assignments.list_teams(teacher, assignment.id)
    third = Enum.find(teams, &(&1.name == "Third"))
    assert has_element?(view, "#team-tab-#{third.id}[aria-selected=true]")
    refute has_element?(view, "#managed-team-#{third.id}[hidden]")
    assert has_element?(view, "#managed-team-#{second.id}[hidden]")
  end

  test "teacher sets and clears a submission deadline extension in Toronto local time", %{
    conn: conn
  } do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    student = student_fixture()
    enroll_student(classroom, teacher, student)
    assignment = assignment_fixture(teacher, classroom)

    {:ok, assignment} =
      Assignments.update_assignment(teacher, assignment.id, %{
        deadline_at: ~U[2026-10-15 20:30:00Z]
      })

    subject = accept_assignment(assignment, teacher, student)

    {:ok, view, _html} =
      conn
      |> log_in_user(teacher)
      |> live(assignment_path(classroom, assignment))

    assert has_element?(
             view,
             "#submission-#{student.login} button[title='Extend deadline'][aria-label='Revise deadline for Test Student']"
           )

    view
    |> element(
      "#submission-#{student.login} button[aria-label='Revise deadline for Test Student']"
    )
    |> render_click()

    view
    |> form("#deadline-extension-form", extension: %{deadline: "2026-10-16T16:30"})
    |> render_submit()

    persisted = Repo.get!(Subject, subject.id)
    assert DateTime.compare(persisted.extension_until, ~U[2026-10-16 20:30:00Z]) == :eq

    assert has_element?(
             view,
             "#submission-#{student.login} [data-ui='deadline-extension']",
             "Extended deadline"
           )

    assert has_element?(
             view,
             "#submission-#{student.login} button[title='Change deadline']"
           )

    view
    |> element(
      "#submission-#{student.login} button[aria-label='Revise deadline for Test Student']"
    )
    |> render_click()

    view |> element("button[data-ui~='clear-extension']") |> render_click()

    assert Repo.get!(Subject, subject.id).extension_until == nil
    refute has_element?(view, "#submission-#{student.login} [data-ui='deadline-extension']")

    assert has_element?(
             view,
             "#submission-#{student.login} button[title='Extend deadline']"
           )
  end

  test "activity charts scale observed pushes across the visible submissions", %{conn: conn} do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    frequent_student = student_fixture()
    occasional_student = student_fixture()
    enroll_student(classroom, teacher, frequent_student)
    enroll_student(classroom, teacher, occasional_student)
    assignment = assignment_fixture(teacher, classroom)
    frequent_subject = accept_assignment(assignment, teacher, frequent_student)
    occasional_subject = accept_assignment(assignment, teacher, occasional_student)
    record_pushes(assignment, frequent_subject, 10)
    record_pushes(assignment, occasional_subject, 1)

    {:ok, view, _html} =
      conn
      |> log_in_user(teacher)
      |> live(assignment_path(classroom, assignment))

    frequent_chart = chart_y_values(view, frequent_student.login)
    occasional_chart = chart_y_values(view, occasional_student.login)

    assert has_element?(
             view,
             "#submission-#{frequent_student.login} svg[aria-label^='Daily pushes']"
           )

    assert Enum.min(frequent_chart) == 2
    assert Enum.min(occasional_chart) > 2
    assert Enum.all?(frequent_chart ++ occasional_chart, &(&1 in 2..30))
  end

  test "a teacher cannot open another classroom assignment or retry its repository", %{conn: conn} do
    %{user: teacher} = bootstrap_fixture()
    other_teacher = user_fixture()
    teacher_membership_fixture(other_teacher)
    classroom = classroom_fixture(teacher)
    assignment = assignment_fixture(teacher, classroom)
    student = student_fixture()
    enroll_student(classroom, teacher, student)
    subject = accept_assignment(assignment, teacher, student)
    {:ok, _} = Assignments.repository_provisioning_failed(subject.id, "github_unavailable")

    {:ok, view, html} =
      conn
      |> log_in_user(other_teacher)
      |> live(assignment_path(classroom, assignment))

    refute html =~ assignment.title
    render_click(view, "retry_repository", %{"subject_id" => to_string(subject.id)})
    assert Repo.get_by!(Repository, subject_id: subject.id).state == "failed"
  end

  defp enroll_student(classroom, teacher, student) do
    {:ok, invitation} = Classrooms.create_class_invitation(teacher, classroom.id)

    {:ok, _enrollment} =
      Classrooms.accept_class_invitation(student, invitation.token, %{
        name: "Test Student",
        student_id: "2026001"
      })
  end

  defp accept_assignment(assignment, teacher, student) do
    {:ok, invitation} = Assignments.create_assignment_invitation(teacher, assignment.id)

    {:ok, %{subject: subject}} =
      Assignments.accept_assignment_invitation(student, invitation.token, %{
        name: "Test Student",
        student_id: "2026001"
      })

    subject
  end

  defp record_pushes(assignment, subject, count) do
    github_repository_id = System.unique_integer([:positive, :monotonic])

    {:ok, repository} =
      Assignments.repository_provisioned(subject.id, %{
        github_repository_id: github_repository_id,
        owner_login: "test-org",
        name: "assignment-#{subject.id}",
        full_name: "test-org/assignment-#{subject.id}",
        html_url: "https://github.com/test-org/assignment-#{subject.id}"
      })

    observed_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    for index <- 1..count do
      commit_sha = index |> Integer.to_string(16) |> String.pad_leading(40, "0")

      {:ok, _push} =
        Submissions.record_push(
          assignment.id,
          repository.id,
          commit_sha,
          "main",
          observed_at,
          "activity-#{subject.id}-#{index}"
        )
    end
  end

  defp chart_y_values(view, login) do
    html = view |> element("#submission-#{login} polyline") |> render()
    [_, points] = Regex.run(~r/points="([0-9., ]+)"/, html)

    points
    |> String.split()
    |> Enum.map(fn point ->
      [_, y] = String.split(point, ",")
      String.to_integer(y)
    end)
  end

  defp assignment_path(classroom, assignment),
    do: "/classrooms/#{classroom.slug}/assignments/#{assignment.slug}"
end
