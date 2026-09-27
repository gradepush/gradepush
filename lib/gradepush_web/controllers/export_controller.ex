defmodule GradePushWeb.ExportController do
  use GradePushWeb, :controller

  alias GradePush.{Assignments, Classrooms}
  alias GradePushWeb.CSV

  def submissions(conn, %{"slug" => slug, "assignment" => key}) do
    actor = conn.assigns.current_user

    with {:ok, classroom} <- Classrooms.get_classroom(actor, slug),
         {:ok, assignment} <- Assignments.get_assignment(actor, classroom.id, key),
         {:ok, students} <- Classrooms.list_students(actor, classroom.id),
         {:ok, subjects} <- Assignments.list_submissions(actor, assignment.id) do
      subjects_by_user = index_subjects(subjects)
      rows = Enum.map(students, &row(&1.user, subjects_by_user[&1.user_id]))

      headers = [
        gettext("Name"),
        gettext("Student ID"),
        gettext("GitHub account"),
        gettext("Team"),
        gettext("Repository"),
        gettext("Accepted at"),
        gettext("Last push received at"),
        gettext("Commit"),
        gettext("Score"),
        gettext("Maximum score")
      ]

      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> send_download({:binary, CSV.encode([headers | rows])},
        filename: assignment.slug <> "-submissions.csv",
        content_type: "text/csv; charset=utf-8"
      )
    else
      _ -> send_resp(conn, :not_found, "Not found")
    end
  end

  defp index_subjects(subjects) do
    Enum.reduce(subjects, %{}, fn subject, index ->
      ids =
        case subject.kind do
          "individual" ->
            [subject.user_id]

          "team" ->
            subject.team.members |> Enum.filter(&is_nil(&1.left_at)) |> Enum.map(& &1.user_id)
        end

      Enum.reduce(ids, index, &Map.put(&2, &1, subject))
    end)
  end

  defp row(user, nil),
    do: [
      user.student_name || user.name,
      user.student_id,
      user.login,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil
    ]

  defp row(user, subject) do
    push = subject.latest_push
    grade = subject.latest_grade

    [
      user.student_name || user.name,
      user.student_id,
      user.login,
      if(subject.kind == "team", do: subject.team.name),
      subject.repository && subject.repository.html_url,
      iso8601(subject.accepted_at),
      push && iso8601(push.observed_at),
      push && push.commit_sha,
      grade && grade.score,
      grade && grade.max_score
    ]
  end

  defp iso8601(nil), do: nil
  defp iso8601(datetime), do: DateTime.to_iso8601(datetime)
end
