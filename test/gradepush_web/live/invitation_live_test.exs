defmodule GradePushWeb.InvitationLiveTest do
  use GradePushWeb.ConnCase, async: true, group: :institution

  import Phoenix.LiveViewTest
  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures

  alias GradePush.{Accounts, Assignments, Classrooms, Repo}
  alias GradePush.Accounts.InstitutionMembership

  setup do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    %{teacher: teacher, classroom: classroom}
  end

  test "a bearer sees the invitation before sign-in, but no team choices or enrollment", c do
    assignment = assignment_fixture(c.teacher, c.classroom, %{kind: "team"})
    {:ok, invite} = Assignments.create_assignment_invitation(c.teacher, assignment.id)
    path = "/join/assignment/#{invite.token}"
    conn = c.conn |> init_test_session(%{ui_preview: false}) |> get(path)
    assert get_session(conn, :return_to) == path
    {:ok, view, _} = live(conn)
    assert has_element?(view, "h1", assignment.title)
    assert has_element?(view, "#invitation-card img[alt='GradePush']")
    assert has_element?(view, "#invitation-classroom", c.classroom.title)
    assert has_element?(view, "#invitation-classroom", c.classroom.code)
    assert has_element?(view, "#invitation-classroom", "Fall 2026")
    refute has_element?(view, "#invitation-card time")
    refute has_element?(view, "header, footer, #invitation-instructions")
    {:ok, public_invitation} = Assignments.assignment_invitation(invite.token)
    refute Map.has_key?(public_invitation, :organization)
    refute render(view) =~ "GitHub organization"
    assert has_element?(view, "a[href='/auth/github']", "Continue on GitHub")
    refute has_element?(view, "#accept-invitation-form")
    refute has_element?(view, "select")
    render_click(view, "accept", %{})
    assert_redirect(view, "/auth/sign-in")
    assert {:ok, []} = Classrooms.list_students(c.teacher, c.classroom.id)
  end

  test "assignment invitations show an optional deadline and omit an unset classroom term", c do
    classroom = classroom_fixture(c.teacher, %{semester: nil, academic_year: nil})
    assignment = assignment_fixture(c.teacher, classroom)
    deadline = ~U[2026-10-19 03:59:00.000000Z]

    {:ok, _} =
      Assignments.update_assignment(c.teacher, assignment.id, %{deadline_at: deadline})

    {:ok, invite} = Assignments.create_assignment_invitation(c.teacher, assignment.id)
    {:ok, view, _} = live(c.conn, "/join/assignment/#{invite.token}?locale=fr")
    assert has_element?(view, "#invitation-classroom", classroom.code)
    refute has_element?(view, "#invitation-classroom", "·")

    assert has_element?(
             view,
             "#invitation-card time[datetime='2026-10-19T03:59:00.000000Z']",
             "À remettre le #{GradePushWeb.Presentation.datetime(deadline, "fr")}"
           )
  end

  test "one click enrolls a new GitHub account, ignores declared identity, and is idempotent",
       c do
    student = user_fixture(%{name: nil, login: "first-time-learner"})
    assignment = assignment_fixture(c.teacher, c.classroom)
    {:ok, invite} = Assignments.create_assignment_invitation(c.teacher, assignment.id)
    conn = log_in_user(c.conn, student)
    {:ok, view, _} = live(conn, "/join/assignment/#{invite.token}")
    assert has_element?(view, "#invitation-account", student.login)
    refute has_element?(view, "input[name='profile[name]']")
    refute has_element?(view, "input[name='profile[student_id]']")

    result =
      render_click(view, "accept", %{"profile" => %{"name" => "Forged", "student_id" => "secret"}})

    assert_redirect(
      view,
      "/student/classrooms/#{c.classroom.slug}/assignments/#{assignment.slug}"
    )

    {:ok, redirected_conn} = follow_redirect(result, conn)
    {:ok, detail, _html} = live(redirected_conn)
    assert has_element?(detail, "#student-content h1", assignment.title)
    refute has_element?(detail, "[role=alert]")
    refute has_element?(detail, "#invitation-card")

    membership = Repo.get_by!(InstitutionMembership, user_id: student.id, role: :student)
    assert is_nil(membership.student_id)
    assert is_nil(membership.student_name)
    assert {:ok, [subject]} = Assignments.list_submissions(c.teacher, assignment.id)
    assert {:ok, accepted} = Assignments.accept_assignment_invitation(student, invite.token, %{})
    assert accepted.subject.id == subject.id
    assert {:ok, %{entries: [entry]}} = Accounts.list_institution_students(c.teacher)
    assert entry.name == student.login

    {:ok, updated} =
      Accounts.upsert_github_user(%{
        github_id: student.github_id,
        login: student.login,
        name: "Camille Updated"
      })

    {:ok, teacher_view, _} =
      c.conn |> log_in_user(c.teacher) |> live("/classrooms/#{c.classroom.slug}?tab=students")

    assert has_element?(teacher_view, "#student-#{updated.login}", "Camille Updated")
    refute has_element?(teacher_view, "[data-ui=student-labels]", "Student ID")
    assert {:ok, %{entries: [entry]}} = Accounts.list_institution_students(c.teacher)
    assert entry.name == "Camille Updated"
  end

  test "student teams support creating and joining, and report a team filled since loading", c do
    assignment = assignment_fixture(c.teacher, c.classroom, %{kind: "team", team_size: 2})
    {:ok, invite} = Assignments.create_assignment_invitation(c.teacher, assignment.id)
    first = user_fixture()
    second = user_fixture()
    third = user_fixture()
    {:ok, creator, _} = c.conn |> log_in_user(first) |> live("/join/assignment/#{invite.token}")

    creator
    |> form("#accept-invitation-form", profile: %{team_id: "", team_name: "Pioneers"})
    |> render_submit()

    assert_redirect(creator)
    {:ok, [team]} = Assignments.list_joinable_teams(second, invite.token)
    {:ok, joiner, _} = c.conn |> log_in_user(second) |> live("/join/assignment/#{invite.token}")

    joiner
    |> form("#accept-invitation-form", profile: %{team_id: to_string(team.id)})
    |> render_change()

    refute has_element?(joiner, "input[name='profile[team_name]']")
    {:ok, _} = Assignments.accept_assignment_invitation(third, invite.token, %{team_id: team.id})

    joiner
    |> form("#accept-invitation-form", profile: %{team_id: to_string(team.id)})
    |> render_submit()

    assert has_element?(joiner, "[role=alert]", "This team is full")
    refute Accounts.student?(second)
  end

  test "teacher-assigned teams show the assigned name and prevent choosing a different team", c do
    assignment = assignment_fixture(c.teacher, c.classroom, %{kind: "team", team_mode: "teacher"})
    {:ok, invite} = Assignments.create_assignment_invitation(c.teacher, assignment.id)
    student = user_fixture()
    conn = log_in_user(c.conn, student)
    {:ok, waiting, _} = live(conn, "/join/assignment/#{invite.token}")
    assert has_element?(waiting, "button[type=submit][disabled]")
    assert has_element?(waiting, "[role=status]", "assign you to a team")
    refute has_element?(waiting, "select")

    assert {:error, :team_assignment_required} =
             Assignments.accept_assignment_invitation(student, invite.token, %{})

    refute Accounts.student?(student)

    {:ok, class_invite} = Classrooms.create_class_invitation(c.teacher, c.classroom.id)
    {:ok, _} = Classrooms.accept_class_invitation(student, class_invite.token, %{})
    {:ok, team} = Assignments.create_team(c.teacher, assignment.id, %{name: "Assigned team"})
    {:ok, _} = Assignments.add_team_member(c.teacher, assignment.id, team.id, student.id)
    {:ok, assigned, _} = live(conn, "/join/assignment/#{invite.token}")
    assert has_element?(assigned, "#accept-invitation-form", "Assigned team")
    refute has_element?(assigned, "button[type=submit][disabled]")
    assigned |> form("#accept-invitation-form") |> render_submit()
    assert_redirect(assigned)
  end

  test "revocation after loading denies acceptance without enrolling the user", c do
    assignment = assignment_fixture(c.teacher, c.classroom)
    {:ok, invite} = Assignments.create_assignment_invitation(c.teacher, assignment.id)
    student = user_fixture()
    {:ok, view, _} = c.conn |> log_in_user(student) |> live("/join/assignment/#{invite.token}")
    {:ok, _} = Assignments.revoke_assignment_invitation(c.teacher, assignment.id)
    view |> form("#accept-invitation-form") |> render_submit()
    assert has_element?(view, "[role=alert]", "expired")
    refute Accounts.student?(student)
  end

  test "preview fixture tokens reveal nothing when UI preview is disabled", c do
    {:ok, view, _} =
      c.conn
      |> init_test_session(%{ui_preview: false})
      |> live("/join/assignment/preview-individual")

    assert has_element?(view, "h1", "Invitation unavailable")
    refute has_element?(view, "#invitation-account")
  end

  test "preview acceptance navigates to a simulated student detail without creating enrollment",
       c do
    {:ok, view, _} = live(c.conn, "/join/assignment/preview-individual")
    result = view |> form("#accept-invitation-form") |> render_submit()
    {:ok, redirected_conn} = follow_redirect(result, c.conn)
    {:ok, detail, _} = live(redirected_conn)
    assert has_element?(detail, "#student-content h1", "Premiers pas en Python")
    refute has_element?(detail, "[role=alert]")
    assert {:ok, []} = Classrooms.list_students(c.teacher, c.classroom.id)

    conn = init_test_session(c.conn, %{ui_preview: false})

    assert {:error, {:redirect, %{to: "/auth/sign-in"}}} =
             live(conn, "/student/classrooms/preview-programming/assignments/preview-individual")
  end
end
