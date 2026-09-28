defmodule GradePushWeb.TeacherWorkspace do
  @moduledoc false
  use Gettext, backend: GradePushWeb.Gettext

  alias GradePush.{Submissions, Time}
  alias GradePushWeb.Presentation

  def classroom(classroom, enrollments \\ []) do
    teachers = Enum.map(classroom.teachers, &teacher/1)
    connection = Map.get(classroom, :github_connection)

    %{
      id: classroom.id,
      slug: classroom.slug,
      title: Presentation.text(classroom.title),
      description: Presentation.text(classroom.description),
      code: classroom.code || "",
      session: classroom.session || "",
      semester: classroom.semester,
      academic_year: classroom.academic_year,
      students: Map.get(classroom, :students_count, 0),
      assignments: Map.get(classroom, :assignments_count, 0),
      organization: if(connection, do: connection.login, else: ""),
      github_connection_id: classroom.github_connection_id,
      teachers: teachers,
      members: Enum.map(enrollments, &student/1)
    }
  end

  def student(enrollment) do
    user = enrollment.user
    name = user.student_name || display_name(user)

    %{
      id: user.id,
      name: name,
      initials: Presentation.initials(name),
      avatar_url: user.avatar_url,
      handle: user.login,
      identifier: user.student_id || "",
      joined_at: Map.get(enrollment, :joined_at) || Map.get(enrollment, :inserted_at)
    }
  end

  def team(team, number, team_size) do
    members = Enum.map(team.members, &student/1)

    %{
      id: team.id,
      number: number,
      name: team.name,
      members: members,
      member_ids: MapSet.new(members, & &1.id),
      can_add?: length(members) < team_size
    }
  end

  def teacher(%{user: user}), do: teacher(user)

  def teacher(user) do
    name = display_name(user)

    %{
      id: user.id,
      name: name,
      initials: Presentation.initials(name),
      avatar_url: user.avatar_url,
      handle: user.login,
      color: "blue"
    }
  end

  def organization(connection) do
    %{id: connection.id, login: connection.login}
  end

  def assignment(assignment, classroom) do
    tests = Enum.map(Map.get(assignment, :tests, []), &test/1)
    deadline = Map.get(assignment, :deadline_at)
    published_at = Map.get(assignment, :published_at)

    %{
      id: assignment.id,
      key: assignment.slug,
      classroom: classroom.slug,
      title: Presentation.text(assignment.title),
      instructions: Presentation.text(assignment.instructions),
      status: if(is_nil(published_at), do: :draft, else: :open),
      kind: kind_label(assignment.kind),
      group?: assignment.kind == "team",
      team_mode: assignment.team_mode,
      team_size: assignment.team_size,
      due: Presentation.datetime_text(deadline),
      deadline_at: deadline,
      deadline_local: Time.format_local(deadline),
      cutoff: assignment.cutoff_enabled,
      tests?: assignment.autograding_enabled,
      test_specs: tests,
      submitted: Map.get(assignment, :submissions_count, 0),
      total: classroom.students,
      repository: assignment.template_repository || "",
      repository_name_pattern: Map.get(assignment, :repository_name_pattern),
      records: %{}
    }
  end

  def assignment_params(nil), do: %{}

  def assignment_params(assignment) do
    %{
      "title" => assignment.title,
      "instructions" => assignment.instructions || "",
      "deadline" => Time.format_local(assignment.deadline_at),
      "cutoff" => to_string(assignment.cutoff_enabled),
      "template" => assignment.template_repository || "",
      "kind" => assignment.kind,
      "team_mode" => assignment.team_mode,
      "team_size" => to_string(assignment.team_size || 2),
      "autograding" => to_string(assignment.autograding_enabled),
      "tests" => Enum.map(Map.get(assignment, :tests, []), &test_params/1)
    }
  end

  def test(test) do
    %{
      name: test.name,
      description: test.description || "",
      type: test.type,
      points: test.points,
      command: test.command || "",
      path: test.path || "",
      input: test.input || "",
      expected: test.expected || ""
    }
  end

  def test_params(test) do
    test
    |> test()
    |> Map.new(fn {key, value} -> {Atom.to_string(key), to_string_if_number(value)} end)
  end

  def details(assignment, classroom, members, subjects, activities, query, filter, locale) do
    tests = assignment.test_specs

    rows =
      if assignment.group? do
        subjects
        |> Enum.with_index(1)
        |> Enum.map(fn {subject, index} ->
          team_row(subject, index, activities, assignment.deadline_at)
        end)
      else
        subject_by_user = Map.new(subjects, &{&1.user_id, &1})

        Enum.map(members, fn member ->
          subject = Map.get(subject_by_user, member.id)
          student_row(member, subject, activities, assignment.deadline_at)
        end)
      end
      |> Enum.filter(&matches?(&1, query, filter))

    instructions = Map.fetch!(assignment.instructions, String.to_existing_atom(locale))

    %{
      rows: rows,
      tests: tests,
      dates: activity_dates(),
      total_points: Enum.sum_by(tests, & &1.points),
      instructions: instructions,
      accepted:
        if(assignment.group?,
          do: Enum.sum_by(subjects, &length(Map.get(&1.team, :members, []))),
          else: length(subjects)
        ),
      total: length(classroom.members)
    }
  end

  defp kind_label("team"), do: %{en: "Team", fr: "Équipe"}
  defp kind_label(_), do: %{en: "Individual", fr: "Individuel"}

  defp student_row(student, nil, _activities, _deadline) do
    Map.merge(student, %{
      key: student.handle,
      subject_id: nil,
      status: :not_accepted,
      repository: nil,
      repository_url: nil,
      repository_state: nil,
      repository_error: nil,
      pushed: nil,
      extension_until: nil,
      extension_label: nil,
      score: nil,
      activity: List.duplicate(0, 14)
    })
  end

  defp student_row(student, subject, activities, deadline_at) do
    activity = Map.get(activities, subject.id, [])
    push = Map.get(subject, :latest_push)
    repository = Map.get(subject, :repository)
    latest_grade = Map.get(subject, :latest_grade)

    Map.merge(student, %{
      key: student.handle,
      subject_id: subject.id,
      status: submission_status(push, deadline(subject, deadline_at)),
      repository: repository_name(repository),
      repository_url: repository_url(repository),
      repository_state: Map.get(repository || %{}, :state),
      repository_error: repository_error(repository),
      pushed: local_date(push_time(push)),
      extension_until: Time.format_local(Map.get(subject, :extension_until)),
      extension_label: local_date(Map.get(subject, :extension_until)),
      score: grade_score(latest_grade),
      grade_untrusted?: match?(%{status: "untrusted"}, latest_grade),
      activity: activity_counts(activity)
    })
  end

  defp team_row(subject, index, activities, deadline_at) do
    team = subject.team

    members = Enum.map(team.members, fn member -> student(member) end)
    activity = Map.get(activities, subject.id, [])
    push = Map.get(subject, :latest_push)
    repository = Map.get(subject, :repository)

    %{
      key: "team-#{team.id}",
      subject_id: subject.id,
      name: team.name || gettext("Team %{number}", number: index),
      members: Enum.map_join(members, ", ", & &1.name),
      member_profiles: members,
      search_terms: Enum.map_join(members, " ", &"#{&1.name} #{&1.identifier} #{&1.handle}"),
      status: submission_status(push, deadline(subject, deadline_at)),
      repository: repository_name(repository),
      repository_url: repository_url(repository),
      repository_state: Map.get(repository || %{}, :state),
      repository_error: repository_error(repository),
      pushed: local_date(push_time(push)),
      extension_until: Time.format_local(Map.get(subject, :extension_until)),
      extension_label: local_date(Map.get(subject, :extension_until)),
      score: grade_score(Map.get(subject, :latest_grade)),
      grade_untrusted?: match?(%{status: "untrusted"}, Map.get(subject, :latest_grade)),
      activity: activity_counts(activity)
    }
  end

  defp matches?(row, query, filter) do
    text = Enum.join([row[:name], row[:handle], row[:identifier], row[:search_terms]], " ")

    String.contains?(String.downcase(text), String.downcase(query)) and
      (filter == "all" or Atom.to_string(row.status) == filter)
  end

  defp submission_status(nil, _deadline), do: :no_push

  defp submission_status(push, deadline) do
    pushed_at = push_time(push)

    if deadline && DateTime.compare(pushed_at, deadline) == :gt,
      do: :late,
      else: :pushed
  end

  defp deadline(subject, assignment_deadline),
    do: Submissions.effective_deadline(assignment_deadline, Map.get(subject, :extension_until))

  defp push_time(nil), do: nil
  defp push_time(push), do: Map.get(push, :observed_at) || Map.get(push, :pushed_at)

  defp local_date(nil), do: nil
  defp local_date(datetime), do: Presentation.datetime_text(datetime)

  defp repository_name(nil), do: nil
  defp repository_name(%{state: state}) when state != "ready", do: nil
  defp repository_name(repository), do: repository.full_name || repository.name

  defp repository_url(%{state: "ready", html_url: url}) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: "github.com", userinfo: nil} -> url
      _ -> nil
    end
  end

  defp repository_url(_), do: nil

  defp repository_error(%{state: "failed", last_error: "permission_denied"}),
    do: gettext("Check the GradePush GitHub App permissions, then retry repository setup.")

  defp repository_error(%{state: "failed", last_error: "repository_conflict"}),
    do: gettext("A repository with this name already exists. Check the GitHub organization.")

  defp repository_error(%{state: "failed", last_error: "workflow_setup_failed"}),
    do: gettext("The automatic tests could not be copied to GitHub. Retry repository setup.")

  defp repository_error(%{state: "failed", last_error: "collaborator_setup_failed"}),
    do: gettext("Student access could not be added to GitHub. Retry repository setup.")

  defp repository_error(%{state: "failed"}),
    do: gettext("GitHub could not create the repository. Check the connection and retry.")

  defp repository_error(_), do: nil

  defp grade_score(nil), do: nil
  defp grade_score(%{status: "untrusted"}), do: nil
  defp grade_score(%{score: %Decimal{} = score}), do: Decimal.to_string(score, :normal)
  defp grade_score(grade), do: Map.get(grade, :score) || Map.get(grade, :points_earned)

  defp activity_dates do
    today = DateTime.now!(Time.timezone()) |> DateTime.to_date()
    Enum.map(-13..0, &Date.add(today, &1))
  end

  defp activity_counts(days) do
    counts = Map.new(days, &{&1.date, &1.count})
    Enum.map(activity_dates(), &Map.get(counts, &1, 0))
  end

  defp display_name(%{name: name, login: login}) when name in [nil, ""], do: login
  defp display_name(%{name: name}), do: name

  defp to_string_if_number(nil), do: ""
  defp to_string_if_number(value) when is_integer(value), do: Integer.to_string(value)
  defp to_string_if_number(value), do: value
end
