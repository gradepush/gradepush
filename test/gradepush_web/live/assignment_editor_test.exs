defmodule GradePushWeb.AssignmentEditorTest do
  use GradePushWeb.ConnCase, async: true, group: :institution
  import Phoenix.LiveViewTest

  test "removing a test needs confirmation and cancellation preserves all fields", %{conn: conn} do
    {:ok, view, _} = live(conn, "/classrooms/programming/assignments/new")
    view |> form("#assignment-form", assignment: %{autograding: "true"}) |> render_change()
    view |> element("button", "Add test") |> render_click()
    view |> element("button", "Add test") |> render_click()

    view
    |> form("#assignment-form",
      assignment: %{
        autograding: "true",
        tests: %{
          "0" => %{
            name: "Build",
            type: "command",
            command: "make",
            points: "7",
            description: "Compile the project."
          },
          "1" => %{name: "README", type: "command", command: "cat README.md", points: "3"}
        }
      }
    )
    |> render_change()

    render_click(view, "confirm_remove_assignment_test")

    for index <- ["-1", "2", "invalid"] do
      render_click(view, "remove_assignment_test", %{"index" => index})
      refute has_element?(view, "[role=dialog]")
    end

    view |> element("#assignment_tests_0-remove") |> render_click()
    assert has_element?(view, "[role=dialog]", "Remove test?")
    assert has_element?(view, "[role=dialog]", "Build")
    assert has_element?(view, "#assignment_tests_0-card")
    view |> element("#cancel-test-removal") |> render_click()
    refute has_element?(view, "[role=dialog]")
    assert has_element?(view, "#assignment_tests_0_command[value=make]")
    assert has_element?(view, "#assignment_tests_0_description", "Compile the project.")
    view |> element("#assignment_tests_0-remove") |> render_click()
    view |> element("button[phx-click=confirm_remove_assignment_test]") |> render_click()
    refute has_element?(view, "[role=dialog]")
    assert view |> element("[data-ui=automatic-test] [data-test-name]") |> render() =~ "README"
    refute has_element?(view, "input[value=Build]")
    assert_push_event(view, "assignment-test-removed", %{})
    render_click(view, "confirm_remove_assignment_test")
    assert has_element?(view, "input[value=README]")
  end

  test "create, inspect, edit and return to the class without losing the new assignment", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/classrooms/programming")
    view |> element("a", "New assignment") |> render_click()
    assert_patch(view, "/classrooms/programming/assignments/new")
    assert has_element?(view, "input[name='assignment[cutoff]'][type=checkbox][disabled]")

    view
    |> form("#assignment-form",
      assignment: %{title: "Sorting lab", instructions: "## Goals\n\n**Sort** a list."}
    )
    |> render_submit()

    path = assert_patch(view)
    assert has_element?(view, "h1", "Sorting lab")
    assert has_element?(view, ".markdown h4", "Goals")
    assert has_element?(view, ".markdown strong", "Sort")
    assert has_element?(view, "[data-ui~='assignment-facts']", "No deadline")
    refute has_element?(view, "[data-ui~='test-score']")
    assert has_element?(view, "[data-ui~='submissions-heading']", "0 of 28")

    view |> element("a", "Edit assignment") |> render_click()
    assert has_element?(view, "input[name='assignment[title]'][value='Sorting lab']")

    view
    |> form("#assignment-form",
      assignment: %{title: "Sorting algorithms", deadline: "2026-10-15T16:30"}
    )
    |> render_change()

    refute has_element?(view, "input[name='assignment[cutoff]'][type=checkbox][disabled]")
    view |> form("#assignment-form", assignment: %{cutoff: "true"}) |> render_submit()
    assert_patch(view, path)
    assert has_element?(view, "[data-ui~='assignment-facts']", "October 15, 2026 at 16:30")
    render_patch(view, "/classrooms/programming")
    assert has_element?(view, "[data-ui~='assignment']", "Sorting algorithms")
    render_patch(view, path)
    assert has_element?(view, "h1", "Sorting algorithms")
    view |> element("a", "Edit assignment") |> render_click()
    view |> form("#assignment-form", assignment: %{deadline: ""}) |> render_change()
    assert has_element?(view, "#assignment_cutoff[disabled]")
    refute has_element?(view, "#assignment_cutoff[checked]")
  end

  test "invalid values stay in the form and cancellation leaves fixtures unchanged", %{conn: conn} do
    {:ok, view, _} = live(conn, "/classrooms/programming/assignments/new")

    view
    |> form("#assignment-form", assignment: %{title: "", template: "other-org/private"})
    |> render_submit()

    assert has_element?(view, "[role=alert]", "Check the highlighted fields")

    assert has_element?(
             view,
             "#assignment_title[aria-invalid='true'][aria-describedby='assignment_title-errors']"
           )

    assert has_element?(view, "#assignment_title-errors", "can't be blank")
    assert_push_event(view, "focus-invalid", %{id: "assignment-form"})
    assert has_element?(view, "input[value='other-org/private']")
    view |> element("[data-ui~='editor-actions'] a", "Cancel") |> render_click()
    assert_patch(view, "/classrooms/programming")
    refute has_element?(view, "[data-ui~='assignment']:nth-of-type(4)")
  end

  test "tests can be added, removed and scored on a new team assignment", %{conn: conn} do
    {:ok, view, _} = live(conn, "/classrooms/programming/assignments/new")

    view
    |> form("#assignment-form",
      assignment: %{title: "Team lab", kind: "team", autograding: "true"}
    )
    |> render_change()

    view |> element("button", "Add test") |> render_click()

    view
    |> form("#assignment-form",
      assignment: %{
        team_mode: "teacher",
        team_size: "3",
        tests: %{
          "0" => %{
            name: "Source exists",
            description: "Include the entry point for your program.",
            type: "file",
            points: "25"
          }
        }
      }
    )
    |> render_change()

    view
    |> form("#assignment-form", assignment: %{tests: %{"0" => %{path: "main.py"}}})
    |> render_change()

    view |> element("button", "Add test") |> render_click()
    view |> element("button[phx-value-index='1']") |> render_click()
    view |> element("button[phx-click=confirm_remove_assignment_test]") |> render_click()
    view |> form("#assignment-form") |> render_submit()
    path = assert_patch(view)
    assert has_element?(view, "[data-ui~='empty']", "No teams yet")
    view |> element("#assignment-sections a", "Tests") |> render_click()
    assert has_element?(view, "[data-ui~='test-list']", "Source exists")

    assert has_element?(
             view,
             "[data-ui~='test-list'] p",
             "Include the entry point for your program."
           )

    assert has_element?(view, "[data-ui~='test-list']", "25 points")
    assert has_element?(view, "[data-ui~='test-command']", "main.py")
    render_patch(view, path <> "/edit")
    assert has_element?(view, "option[value='teacher'][selected]")
    assert has_element?(view, "input[name='assignment[team_size]'][value='3']")

    assert has_element?(
             view,
             "textarea[name='assignment[tests][0][description]']",
             "Include the entry point for your program."
           )
  end

  test "existing acceptance locks repository settings while editing metadata keeps scores", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/classrooms/programming/assignments/cli/edit")
    assert has_element?(view, "input[name='assignment[template]'][disabled]")
    assert has_element?(view, "select[name='assignment[kind]'][disabled]")
    view |> form("#assignment-form", assignment: %{title: "CLI revised"}) |> render_submit()
    assert_patch(view, "/classrooms/programming/assignments/cli")
    assert has_element?(view, "#submission-camille-roy [data-ui~='test-score']", "60")
    view |> element("a", "Edit assignment") |> render_click()

    assert has_element?(
             view,
             "input[name='assignment[template]'][value='cegep-sorel-tracy/420-110-cli-parser']"
           )

    view
    |> form("#assignment-form", assignment: %{tests: %{"0" => %{points: "50"}}})
    |> render_submit()

    refute has_element?(view, "[data-ui~='test-score']")
    assert has_element?(view, "#submission-amelie-fortin")
  end

  test "invalid cross-class editor route does not expose a form", %{conn: conn} do
    {:ok, view, _} = live(conn, "/classrooms/web-development/assignments/cli/edit")
    assert has_element?(view, "h1", "Assignment not found")
    refute has_element?(view, "#assignment-form")
  end

  test "editing a test description preserves scores and allows clearing the description", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/classrooms/programming/assignments/cli/edit")

    assert has_element?(
             view,
             "textarea[name='assignment[tests][0][description]']",
             "usage instructions"
           )

    view
    |> form("#assignment-form",
      assignment: %{tests: %{"0" => %{description: "Help students discover available options."}}}
    )
    |> render_submit()

    assert has_element?(view, "#submission-camille-roy [data-ui~='test-score']", "60")
    view |> element("#assignment-sections a", "Tests") |> render_click()

    assert has_element?(
             view,
             "[data-ui~='test-list'] p",
             "Help students discover available options."
           )

    view |> element("a", "Edit assignment") |> render_click()

    view
    |> form("#assignment-form", assignment: %{tests: %{"0" => %{description: ""}}})
    |> render_submit()

    view |> element("#assignment-sections a", "Tests") |> render_click()
    refute has_element?(view, "[data-ui~='test-list'] li:first-child p")
    assert has_element?(view, "[data-ui~='test-list'] li:first-child h3", "Help flag")
  end
end
