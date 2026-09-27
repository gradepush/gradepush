defmodule GradePushWeb.StudentLiveTest do
  use GradePushWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures

  alias GradePush.{Accounts, Assignments, Classrooms, Submissions}

  setup do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    assignment = assignment_fixture(teacher, classroom)
    student = user_fixture()
    %{teacher: teacher, classroom: classroom, assignment: assignment, student: student}
  end

  test "student classrooms show localized terms, teachers and only published assignment counts",
       context do
    %{teacher: teacher, classroom: classroom, student: student, conn: conn} = context

    winter =
      classroom_fixture(teacher, %{
        title: "Winter course",
        semester: "winter",
        academic_year: "2027"
      })

    for class <- [classroom, winter] do
      {:ok, invitation} = Classrooms.create_class_invitation(teacher, class.id)

      {:ok, _} =
        Classrooms.accept_class_invitation(student, invitation.token, %{
          name: "Camille",
          student_id: "2026001"
        })
    end

    context.assignment |> Ecto.Changeset.change(published_at: nil) |> GradePush.Repo.update!()
    conn = log_in_user(conn, student)
    {:ok, view, _} = live(conn, "/student/classrooms?locale=fr")
    assert has_element?(view, "[data-ui~='term-group']:first-of-type h2", "Hiver 2027")
    assert has_element?(view, "[data-ui~='term-group']:last-of-type h2", "Automne 2026")

    assert has_element?(
             view,
             "a[href='/student/classrooms/#{classroom.slug}'] [data-ui~='card-counts']",
             "0 devoir"
           )

    assert has_element?(view, "[data-ui~='card-teachers']", teacher.name)
    refute has_element?(view, "#profile-menu [data-ui~='sign-out-group']")
    refute has_element?(view, "#profile-menu [data-ui~='profile-divider']")
    refute has_element?(view, "#profile-menu a[href='/teacher/settings']")

    assignment_fixture(teacher, classroom)

    assert has_element?(
             view,
             "a[href='/student/classrooms/#{classroom.slug}'] [data-ui~='card-counts']",
             "1 devoir"
           )

    {:ok, _} =
      Classrooms.update_classroom(teacher, winter.id, %{
        title: winter.title,
        semester: "summer",
        academic_year: "2025"
      })

    assert has_element?(view, "[data-ui~='term-group']:first-of-type h2", "Automne 2026")
    assert has_element?(view, "[data-ui~='term-group']:last-of-type h2", "Été 2025")
    {:ok, _} = Classrooms.archive_classroom(teacher, winter.id)
    refute has_element?(view, "a[href='/student/classrooms/#{winter.slug}']")
  end

  test "a first-time student accepts an assignment, joins its classroom and sees only their repository",
       context do
    %{
      conn: conn,
      teacher: teacher,
      classroom: classroom,
      assignment: assignment,
      student: student
    } = context

    {:ok, invitation} = Assignments.create_assignment_invitation(teacher, assignment.id)
    conn = log_in_user(conn, student)
    {:ok, view, _} = live(conn, "/join/assignment/#{invitation.token}")

    view
    |> form("#accept-invitation-form", profile: %{name: "Camille Test", student_id: "2026001"})
    |> render_submit()

    path = "/student/classrooms/#{classroom.slug}/assignments/#{assignment.slug}"
    assert_redirect(view, path)
    {:ok, detail, html} = live(conn, path)
    assert html =~ "Your repository is being prepared"

    {:ok, %{subject: subject}} =
      Assignments.get_student_assignment(student, classroom.id, assignment.slug)

    {:ok, _} =
      Assignments.repository_provisioned(subject.id, %{
        github_repository_id: 1001,
        owner_login: "test-org",
        name: "camille-work",
        full_name: "test-org/camille-work",
        html_url: "https://github.com/test-org/camille-work"
      })

    assert has_element?(
             detail,
             "a[href='https://github.com/test-org/camille-work']",
             "Open repository"
           )

    {:ok, _, classrooms_html} = live(conn, "/student/classrooms")
    assert classrooms_html =~ classroom.title
    {:ok, _, assignments_html} = live(conn, "/student/classrooms/#{classroom.slug}")
    assert assignments_html =~ assignment.title
    assert Accounts.get_user(student.id).student_id == "2026001"

    other = user_fixture()

    {:ok, %{subject: other_subject}} =
      Assignments.accept_assignment_invitation(other, invitation.token, %{
        "name" => "Other Student",
        "student_id" => "2026002"
      })

    {:ok, _} =
      Assignments.repository_provisioned(other_subject.id, %{
        github_repository_id: 1002,
        owner_login: "test-org",
        name: "other-work",
        full_name: "test-org/other-work",
        html_url: "https://github.com/test-org/other-work"
      })

    refute render(detail) =~ "other-work"

    {:ok, _} = Classrooms.remove_student(teacher, classroom.id, student.id)
    assert render(detail) =~ "This page is not available."
    refute render(detail) =~ "https://github.com/test-org/camille-work"
  end

  test "a classroom invitation enrolls the student without accepting an assignment", context do
    %{
      conn: conn,
      teacher: teacher,
      classroom: classroom,
      assignment: assignment,
      student: student
    } = context

    {:ok, invitation} = Classrooms.create_class_invitation(teacher, classroom.id)
    conn = log_in_user(conn, student)
    {:ok, view, _} = live(conn, "/join/classroom/#{invitation.token}")

    view
    |> form("#accept-invitation-form", profile: %{name: "Noémie Test", student_id: "2026003"})
    |> render_submit()

    assert_redirect(view, "/student/classrooms/#{classroom.slug}")

    assert {:ok, %{subject: nil}} =
             Assignments.get_student_assignment(student, classroom.id, assignment.slug)

    {:ok, _, html} =
      live(conn, "/student/classrooms/#{classroom.slug}/assignments/#{assignment.slug}")

    assert html =~ "Use your teacher’s assignment invitation"
  end

  test "a personal extension updates the student's list and assignment deadline", context do
    %{
      teacher: teacher,
      classroom: classroom,
      assignment: assignment,
      student: student,
      conn: conn
    } = context

    {:ok, assignment} =
      Assignments.update_assignment(teacher, assignment.id, %{
        deadline_at: ~U[2026-10-01 18:00:00.000000Z]
      })

    {:ok, invitation} = Assignments.create_assignment_invitation(teacher, assignment.id)

    {:ok, %{subject: subject}} =
      Assignments.accept_assignment_invitation(student, invitation.token, %{
        name: "Camille Test",
        student_id: "2026001"
      })

    conn = log_in_user(conn, student)
    {:ok, list, _} = live(conn, "/student/classrooms/#{classroom.slug}")

    {:ok, detail, _} =
      live(conn, "/student/classrooms/#{classroom.slug}/assignments/#{assignment.slug}")

    extension = ~U[2026-10-03 18:00:00Z]

    assert {:ok, _} = Submissions.set_extension(teacher, assignment.id, subject.id, extension)
    assert render(list) =~ GradePushWeb.Presentation.datetime(extension)
    assert render(detail) =~ GradePushWeb.Presentation.datetime(extension)
    refute render(detail) =~ GradePushWeb.Presentation.datetime(assignment.deadline_at)

    later_deadline = ~U[2026-10-05 18:00:00.000000Z]

    assert {:ok, assignment} =
             Assignments.update_assignment(teacher, assignment.id, %{deadline_at: later_deadline})

    assert render(list) =~ GradePushWeb.Presentation.datetime(later_deadline)
    assert render(detail) =~ GradePushWeb.Presentation.datetime(later_deadline)
    refute render(detail) =~ GradePushWeb.Presentation.datetime(extension)

    assert {:ok, _} = Submissions.set_extension(teacher, assignment.id, subject.id, nil)
    assert render(detail) =~ GradePushWeb.Presentation.datetime(assignment.deadline_at)
  end

  test "an unenrolled user cannot read classroom details and invalid invitations reveal no title",
       context do
    %{conn: conn, classroom: classroom, assignment: assignment, student: student} = context
    conn = log_in_user(conn, student)

    {:ok, _, html} =
      live(conn, "/student/classrooms/#{classroom.slug}/assignments/#{assignment.slug}")

    assert html =~ "This page is not available."
    refute html =~ assignment.title
    {:ok, _, invalid} = live(conn, "/join/assignment/invalid-token")
    assert invalid =~ "Invitation unavailable"
    refute invalid =~ classroom.title
  end
end
