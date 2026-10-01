defmodule GradePushWeb.AssignmentTemplatesLiveTest do
  use GradePushWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures

  alias GradePush.GitHub.Fake

  defmodule DelayedTemplates do
    @behaviour GradePush.GitHub

    for {name, arity} <- GradePush.GitHub.behaviour_info(:callbacks),
        name != :list_template_repositories do
      args = Macro.generate_arguments(arity, __MODULE__)

      def unquote(name)(unquote_splicing(args)),
        do: apply(Fake, unquote(name), [unquote_splicing(args)])
    end

    def list_template_repositories(_token, organization) do
      send(
        Application.fetch_env!(:gradepush, :template_test_observer),
        {:templates_requested, self(), organization}
      )

      receive do
        {:templates_result, result} -> result
      after
        5_000 -> {:error, :timeout}
      end
    end
  end

  setup %{conn: conn} do
    previous = Application.fetch_env!(:gradepush, GradePush.GitHub)
    Application.put_env(:gradepush, GradePush.GitHub, adapter: DelayedTemplates)
    Application.put_env(:gradepush, :template_test_observer, self())
    Fake.reset!()

    on_exit(fn ->
      Application.put_env(:gradepush, GradePush.GitHub, previous)
      Application.delete_env(:gradepush, :template_test_observer)
      Fake.reset!()
    end)

    %{user: teacher} = configured_gradepush_fixture()
    classroom = classroom_fixture(teacher)

    %{
      conn: log_in_user(conn, teacher),
      teacher: teacher,
      classroom: classroom,
      path: "/classrooms/#{classroom.slug}/assignments/new"
    }
  end

  test "initial HTML renders without waiting for GitHub", %{conn: conn, path: path} do
    html = conn |> get(path) |> html_response(200)
    assert html =~ "assignment-form"
    refute_received {:templates_requested, _, _}
    assert html =~ "Loading starter templates"
  end

  test "slow templates do not block editing or replace the draft", %{conn: conn, path: path} do
    {:ok, view, _} = live(conn, path)
    assert_receive {:templates_requested, task, "gradepush-test"}
    assert has_element?(view, "[data-ui=template-status][role=status]", "Loading")

    view
    |> form("#assignment-form", assignment: %{title: "Draft kept", instructions: "Keep my work"})
    |> render_change()

    assert has_element?(view, "input[name='assignment[title]'][value='Draft kept']")
    send(task, {:templates_result, Fake.list_template_repositories("unused", "gradepush-test")})
    render_async(view)

    assert has_element?(view, "input[name='assignment[title]'][value='Draft kept']")
    assert has_element?(view, "textarea[name='assignment[instructions]']", "Keep my work")
    assert has_element?(view, "#assignment-templates option[value='gradepush-test/starter']")
    refute has_element?(view, "[data-ui=template-status]")
    refute_received {:templates_requested, _, _}
  end

  test "failed loading can be retried without losing the draft", %{conn: conn, path: path} do
    {:ok, view, _} = live(conn, path)
    assert_receive {:templates_requested, task, _}
    view |> form("#assignment-form", assignment: %{title: "Retry draft"}) |> render_change()
    send(task, {:templates_result, {:error, :timeout}})
    render_async(view)

    assert has_element?(view, "[data-ui=template-status][role=alert]", "Could not load")
    view |> element("button", "Retry loading templates") |> render_click()
    assert_receive {:templates_requested, retry, _}
    send(retry, {:templates_result, Fake.list_template_repositories("unused", "gradepush-test")})
    render_async(view)
    assert has_element?(view, "input[name='assignment[title]'][value='Retry draft']")
    refute has_element?(view, "[data-ui=template-status]")
  end

  test "an existing template is preserved when saving before suggestions finish", %{
    conn: conn,
    teacher: teacher,
    classroom: classroom
  } do
    assignment = assignment_fixture(teacher, classroom)

    {:ok, assignment} =
      GradePush.Assignments.update_assignment(teacher, assignment.id, %{
        template_repository: "gradepush-test/starter"
      })

    path = "/classrooms/#{classroom.slug}/assignments/#{assignment.slug}"
    {:ok, view, _} = live(conn, path <> "/edit")
    assert_receive {:templates_requested, task, _}
    monitor = Process.monitor(task)

    view
    |> form("#assignment-form", assignment: %{title: "Saved during loading"})
    |> render_submit()

    assert_patch(view, path)
    assert_receive {:DOWN, ^monitor, :process, ^task, _}

    {:ok, stored} = GradePush.Assignments.get_assignment(teacher, classroom.id, assignment.slug)
    assert stored.title == "Saved during loading"
    assert stored.template_repository == "gradepush-test/starter"
  end

  test "leaving the editor cancels its pending load", %{
    conn: conn,
    path: path,
    classroom: classroom
  } do
    {:ok, view, _} = live(conn, path)
    assert_receive {:templates_requested, task, _}
    monitor = Process.monitor(task)
    render_patch(view, "/classrooms/#{classroom.slug}")
    assert_receive {:DOWN, ^monitor, :process, ^task, _}
    refute has_element?(view, "#assignment-form")
    refute has_element?(view, "[data-ui=template-status]")

    render_patch(view, path)
    assert_receive {:templates_requested, next, _}
    refute next == task
    send(next, {:templates_result, {:ok, []}})
    render_async(view)
    refute has_element?(view, "#assignment-templates option")
  end
end
