defmodule GradePush.Submissions do
  @moduledoc "Push evidence and trusted GitHub Actions results for assignment repositories."

  import Ecto.Query

  alias GradePush.Accounts.User
  alias GradePush.Assignments.{Assignment, AssignmentTest, Repository, Subject}
  alias GradePush.Classrooms.{Classroom, GitHubConnection}
  alias GradePush.Repo
  alias GradePush.Submissions.{Grade, GradeTest, Push}

  @activity_days 14

  @doc "An extension can only move an existing assignment deadline later."
  def effective_deadline(nil, _extension), do: nil
  def effective_deadline(deadline, nil), do: deadline

  def effective_deadline(deadline, extension) do
    if DateTime.compare(extension, deadline) == :gt, do: extension, else: deadline
  end

  @doc "Records a push using the server-observed delivery time."
  def record_push_for_github_repository(
        github_repository_id,
        commit_sha,
        branch,
        observed_at,
        delivery_id
      )
      when is_integer(github_repository_id) and github_repository_id > 0 do
    case tracked_repository(github_repository_id) do
      %{repository: repository, subject: subject, assignment: assignment} ->
        record_push(
          assignment.id,
          repository.id,
          commit_sha,
          branch,
          observed_at,
          delivery_id,
          subject.id
        )

      nil ->
        {:error, :not_found}
    end
  end

  def record_push_for_github_repository(_, _, _, _, _), do: {:error, :not_found}

  @doc "Returns the expected assignment and workflow identity for a validated GitHub Actions run."
  def workflow_target(github_repository_id)
      when is_integer(github_repository_id) and github_repository_id > 0 do
    case tracked_repository(github_repository_id) do
      %{repository: repository, subject: subject, assignment: assignment, classroom: classroom} ->
        connection = Repo.get(GitHubConnection, classroom.github_connection_id)

        if workflow_available?(assignment, repository, connection) do
          {:ok,
           %{
             assignment_id: assignment.id,
             repository_id: repository.id,
             subject_id: subject.id,
             github_repository_id: repository.github_repository_id,
             installation_id: connection.installation_id,
             owner_login: repository.owner_login,
             repository_name: repository.name,
             workflow_id: repository.workflow_id,
             workflow_path: repository.workflow_path,
             workflow_file_sha: repository.workflow_file_sha,
             tests:
               assignment.id
               |> assignment_tests()
               |> Enum.map(&test_target/1)
           }}
        else
          {:error, :workflow_unavailable}
        end

      nil ->
        {:error, :not_found}
    end
  end

  def workflow_target(_), do: {:error, :not_found}

  @doc "Stores push evidence only for a repository already linked to this assignment."
  def record_push(assignment_id, repository_id, commit_sha, observed_at, delivery_id)
      when is_integer(assignment_id) and is_integer(repository_id) do
    record_push_for_internal_repository(
      assignment_id,
      repository_id,
      commit_sha,
      nil,
      observed_at,
      delivery_id
    )
  end

  def record_push(_, _, _, _, _), do: {:error, :not_found}

  def record_push(assignment_id, repository_id, commit_sha, branch, observed_at, delivery_id)
      when is_integer(assignment_id) and is_integer(repository_id) do
    record_push_for_internal_repository(
      assignment_id,
      repository_id,
      commit_sha,
      branch,
      observed_at,
      delivery_id
    )
  end

  def record_push(_, _, _, _, _, _), do: {:error, :not_found}

  defp record_push_for_internal_repository(
         assignment_id,
         repository_id,
         commit_sha,
         branch,
         observed_at,
         delivery_id
       ) do
    case Repo.get_by(Repository, id: repository_id) do
      %Repository{subject_id: subject_id} ->
        record_push(
          assignment_id,
          repository_id,
          commit_sha,
          branch,
          observed_at,
          delivery_id,
          subject_id
        )

      nil ->
        {:error, :not_found}
    end
  end

  defp record_push(
         assignment_id,
         repository_id,
         commit_sha,
         branch,
         observed_at,
         delivery_id,
         subject_id
       ) do
    with {:ok, context} <- validate_push_target(assignment_id, repository_id, subject_id),
         true <- valid_observed_at?(observed_at),
         :ok <- validate_commit_sha(commit_sha) do
      persist_push(context, repository_id, commit_sha, branch, observed_at, delivery_id)
    else
      false -> {:error, :invalid_observed_at}
      {:error, _reason} = error -> error
    end
  end

  @doc "Records one validated workflow run and its bounded test result summary."
  def record_grade(assignment_id, repository_id, attrs)
      when is_integer(assignment_id) and is_integer(repository_id) and is_map(attrs) do
    with {:ok, context} <- validate_grade_target(assignment_id, repository_id),
         {:ok, normalized} <- normalize_grade(attrs, context.assignment),
         :ok <- require_recorded_push(context.subject.id, repository_id, normalized.commit_sha) do
      Repo.transaction(fn ->
        Repo.query!("SELECT id FROM assignment_repositories WHERE id = $1 FOR UPDATE", [
          repository_id
        ])

        persist_grade(context.subject.id, repository_id, normalized)
      end)
      |> publish_result(context, :grade_recorded)
    end
  end

  def record_grade(_, _, _), do: {:error, :not_found}

  @doc "Persists a visible untrusted workflow result without treating it as a score."
  def record_untrusted_result(assignment_id, repository_id, attrs)
      when is_integer(assignment_id) and is_integer(repository_id) and is_map(attrs) do
    with {:ok, context} <- validate_grade_target(assignment_id, repository_id),
         {:ok, normalized} <- normalize_untrusted_result(attrs),
         :ok <- require_recorded_push(context.subject.id, repository_id, normalized.commit_sha) do
      persist_untrusted_result(context.subject.id, repository_id, normalized)
      |> publish_result(context, :grade_untrusted)
    end
  end

  def record_untrusted_result(_, _, _), do: {:error, :not_found}

  defp workflow_available?(assignment, repository, connection) do
    assignment.autograding_enabled and match?(%GitHubConnection{status: "active"}, connection) and
      workflow_configured?(repository)
  end

  defp workflow_configured?(repository) do
    repository.state == "ready" and not is_nil(repository.workflow_id) and
      is_binary(repository.workflow_path) and is_binary(repository.workflow_file_sha)
  end

  defp persist_push(context, repository_id, commit_sha, branch, observed_at, delivery_id) do
    case Repo.get_by(Push, delivery_id: delivery_id) do
      %Push{} -> duplicate_delivery(delivery_id, repository_id, commit_sha)
      nil -> insert_push(context, repository_id, commit_sha, branch, observed_at, delivery_id)
    end
  end

  defp insert_push(context, repository_id, commit_sha, branch, observed_at, delivery_id) do
    attrs = %{
      subject_id: context.subject.id,
      repository_id: repository_id,
      commit_sha: String.downcase(commit_sha),
      branch: normalize_branch(branch),
      observed_at: utc_microseconds(observed_at),
      delivery_id: delivery_id
    }

    case %Push{} |> Push.changeset(attrs) |> Repo.insert() do
      {:ok, push} ->
        publish_result({:ok, push}, context, :push_recorded)

      {:error, changeset} ->
        recover_duplicate_push(changeset, delivery_id, repository_id, commit_sha)
    end
  end

  defp recover_duplicate_push(changeset, delivery_id, repository_id, commit_sha) do
    if delivery_conflict?(changeset),
      do: duplicate_delivery(delivery_id, repository_id, commit_sha),
      else: {:error, changeset}
  end

  defp persist_grade(subject_id, repository_id, normalized) do
    case Repo.get_by(Grade, repository_id: repository_id, run_id: normalized.run_id) do
      %Grade{commit_sha: commit_sha} = existing when commit_sha == normalized.commit_sha ->
        Repo.preload(existing, :tests)

      %Grade{} ->
        Repo.rollback(:run_conflict)

      nil ->
        insert_grade(subject_id, repository_id, normalized)
    end
  end

  defp insert_grade(subject_id, repository_id, normalized) do
    grade =
      %Grade{subject_id: subject_id, repository_id: repository_id}
      |> Grade.changeset(
        Map.take(normalized, [:commit_sha, :run_id, :status, :score, :max_score, :html_url])
      )
      |> Repo.insert!()

    Enum.each(normalized.tests, fn test ->
      %GradeTest{result_id: grade.id} |> GradeTest.changeset(test) |> Repo.insert!()
    end)

    Repo.preload(grade, :tests)
  end

  defp normalize_untrusted_result(attrs) do
    with :ok <- validate_commit_sha(field(attrs, :commit_sha)),
         true <- positive_run_id?(field(attrs, :run_id)),
         true <- field(attrs, :reason) == "workflow_modified",
         true <- optional_github_url?(field(attrs, :html_url)) do
      {:ok,
       %{
         commit_sha: String.downcase(field(attrs, :commit_sha)),
         run_id: field(attrs, :run_id),
         status: "untrusted",
         score: Decimal.new(0),
         max_score: Decimal.new(0),
         html_url: field(attrs, :html_url),
         reason: "workflow_modified"
       }}
    else
      false -> {:error, :invalid_untrusted_result}
      {:error, _} = error -> error
    end
  end

  defp positive_run_id?(id), do: is_integer(id) and id > 0
  defp optional_github_url?(nil), do: true
  defp optional_github_url?(url), do: valid_github_url?(url)

  defp persist_untrusted_result(subject_id, repository_id, normalized) do
    case Repo.get_by(Grade, repository_id: repository_id, run_id: normalized.run_id) do
      %Grade{commit_sha: commit_sha, status: "untrusted"} = grade
      when commit_sha == normalized.commit_sha ->
        {:ok, grade}

      %Grade{} ->
        {:error, :run_conflict}

      nil ->
        %Grade{subject_id: subject_id, repository_id: repository_id}
        |> Grade.changeset(normalized)
        |> Repo.insert()
    end
  end

  defp publish_result({:ok, record}, context, event) do
    broadcast_submission(context.assignment, context.subject, event)
    {:ok, record}
  end

  defp publish_result({:error, _} = error, _context, _event), do: error

  @doc "Attaches each submission's latest push and grade using two batched queries."
  def enrich_subjects([]), do: []

  def enrich_subjects(subjects) when is_list(subjects) do
    ids = Enum.map(subjects, & &1.id)

    pushes = latest_by_subject(Push, ids, asc: :subject_id, desc: :observed_at, desc: :id)

    grades = latest_grades_for_latest_pushes(ids)

    Enum.map(subjects, fn subject ->
      latest_push = Map.get(pushes, subject.id)
      latest_grade = Map.get(grades, subject.id)

      %{subject | latest_push: latest_push, latest_grade: latest_grade}
    end)
  end

  @doc "Aggregates daily push activity over the chart window without truncating active students."
  def list_assignment_activity(%User{} = actor, assignment_id) when is_integer(assignment_id) do
    with %Assignment{} = assignment <- Repo.get(Assignment, assignment_id),
         {:ok, _classroom} <-
           GradePush.Classrooms.classroom_for_teacher(actor, assignment.classroom_id) do
      timezone = GradePush.Time.timezone()
      first_date = DateTime.now!(timezone) |> DateTime.to_date() |> Date.add(1 - @activity_days)
      {:ok, first_day} = DateTime.new(first_date, ~T[00:00:00], timezone)
      first_instant = DateTime.shift_zone!(first_day, "Etc/UTC")

      activity =
        from(push in Push,
          join: subject in Subject,
          on: subject.id == push.subject_id,
          where: subject.assignment_id == ^assignment_id and push.observed_at >= ^first_instant,
          group_by: [
            push.subject_id,
            selected_as(:activity_date)
          ],
          select: %{
            subject_id: push.subject_id,
            date:
              selected_as(
                type(
                  fragment("date(timezone(?, timezone('UTC', ?)))", ^timezone, push.observed_at),
                  :date
                ),
                :activity_date
              ),
            count: count(push.id)
          }
        )
        |> Repo.all()
        |> Enum.group_by(& &1.subject_id)

      {:ok, activity}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def list_assignment_activity(_, _), do: {:error, :unauthorized}

  @doc "Sets or clears a student's deadline extension for an assignment."
  def set_extension(%User{} = actor, assignment_id, subject_id, extension_until)
      when is_integer(assignment_id) and is_integer(subject_id) do
    extension_until =
      case extension_until do
        %DateTime{} = datetime -> utc_microseconds(datetime)
        other -> other
      end

    with %Assignment{} = assignment <- Repo.get(Assignment, assignment_id),
         {:ok, _classroom} <-
           GradePush.Classrooms.classroom_for_teacher(actor, assignment.classroom_id),
         %Subject{assignment_id: ^assignment_id} = subject <- Repo.get(Subject, subject_id),
         true <- is_nil(extension_until) or valid_observed_at?(extension_until),
         :ok <- validate_extension(assignment, extension_until) do
      subject
      |> Ecto.Changeset.change(extension_until: extension_until)
      |> Repo.update()
      |> case do
        {:ok, updated} ->
          broadcast_submission(assignment, updated, :extension_changed)
          {:ok, updated}

        error ->
          error
      end
    else
      false -> {:error, :invalid_extension}
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def set_extension(_, _, _, _), do: {:error, :unauthorized}

  defp validate_extension(_assignment, nil), do: :ok

  defp validate_extension(%Assignment{deadline_at: nil}, _extension_until),
    do: {:error, :deadline_required}

  defp validate_extension(%Assignment{deadline_at: deadline}, extension_until) do
    if DateTime.compare(extension_until, deadline) == :gt,
      do: :ok,
      else: {:error, :extension_must_be_later}
  end

  defp validate_push_target(assignment_id, repository_id, subject_id) do
    query =
      from(repository in Repository,
        join: subject in Subject,
        on: subject.id == repository.subject_id,
        join: assignment in Assignment,
        on: assignment.id == subject.assignment_id,
        where:
          repository.id == ^repository_id and subject.id == ^subject_id and
            assignment.id == ^assignment_id,
        select: {repository, subject, assignment}
      )

    case Repo.one(query) do
      {repository, subject, assignment} ->
        {:ok, %{repository: repository, subject: subject, assignment: assignment}}

      nil ->
        {:error, :not_found}
    end
  end

  defp validate_grade_target(assignment_id, repository_id) do
    query =
      from(repository in Repository,
        join: subject in Subject,
        on: subject.id == repository.subject_id,
        join: assignment in Assignment,
        on: assignment.id == subject.assignment_id,
        where: repository.id == ^repository_id and assignment.id == ^assignment_id,
        select: {repository, subject, assignment}
      )

    case Repo.one(query) do
      {%Repository{} = repository, %Subject{} = subject,
       %Assignment{autograding_enabled: true} = assignment} ->
        {:ok, %{repository: repository, subject: subject, assignment: assignment}}

      _ ->
        {:error, :not_found}
    end
  end

  defp normalize_grade(attrs, assignment) do
    commit_sha = field(attrs, :commit_sha)
    run_id = field(attrs, :run_id)
    status = field(attrs, :status)
    html_url = field(attrs, :html_url)
    tests = field(attrs, :tests) || []
    configured_tests = assignment_tests(assignment.id)

    with :ok <- validate_commit_sha(commit_sha),
         true <- is_integer(run_id) and run_id > 0,
         true <- status in ~w(success failure cancelled timed_out queued in_progress),
         true <- is_list(tests),
         {:ok, normalized_tests} <- normalize_grade_tests(tests, configured_tests),
         {:ok, score} <- decimal_sum(Enum.map(normalized_tests, & &1.points_awarded)),
         {:ok, max_score} <- decimal_sum(Enum.map(normalized_tests, & &1.max_points)),
         {:ok, supplied_score} <- decimal(field(attrs, :score)),
         {:ok, supplied_max} <- decimal(field(attrs, :max_score)),
         true <- Decimal.equal?(score, supplied_score) and Decimal.equal?(max_score, supplied_max),
         true <- is_nil(html_url) or valid_github_url?(html_url) do
      {:ok,
       %{
         commit_sha: String.downcase(commit_sha),
         run_id: run_id,
         status: status,
         score: score,
         max_score: max_score,
         html_url: html_url,
         tests: normalized_tests
       }}
    else
      {:error, _reason} = error -> error
      false -> {:error, :invalid_grade}
    end
  end

  defp normalize_grade_tests(results, configured) do
    configured_by_id = Map.new(configured, &{&1.id, &1})

    normalized =
      Enum.map(results, fn result ->
        test_id = field(result, :test_id)
        definition = Map.get(configured_by_id, test_id)
        status = field(result, :status)
        awarded = field(result, :points_awarded)
        max_points = field(result, :max_points)

        with %AssignmentTest{} <- definition,
             true <- status in ~w(success failure cancelled skipped),
             {:ok, awarded} <- decimal(awarded),
             {:ok, max_points} <- decimal(max_points),
             true <- field(result, :name) == definition.name,
             true <- Decimal.equal?(max_points, Decimal.new(definition.points)),
             true <- Decimal.compare(awarded, Decimal.new(definition.points)) in [:lt, :eq],
             true <- Decimal.compare(awarded, Decimal.new(0)) in [:gt, :eq] do
          {:ok,
           %{
             assignment_test_id: definition.id,
             name: definition.name,
             status: status,
             points_awarded: awarded,
             max_points: max_points
           }}
        else
          _ -> {:error, :invalid_grade_test}
        end
      end)

    with true <- length(normalized) == length(configured),
         true <- Enum.all?(normalized, &match?({:ok, _}, &1)),
         values <- Enum.map(normalized, fn {:ok, value} -> value end),
         true <- length(Enum.uniq_by(values, & &1.assignment_test_id)) == length(configured) do
      {:ok, values}
    else
      _ -> {:error, :invalid_grade_test}
    end
  end

  defp require_recorded_push(subject_id, repository_id, commit_sha) do
    if Repo.exists?(
         from(push in Push,
           where:
             push.subject_id == ^subject_id and push.repository_id == ^repository_id and
               push.commit_sha == ^commit_sha
         )
       ),
       do: :ok,
       else: {:error, :push_not_recorded}
  end

  defp tracked_repository(github_repository_id) do
    Repo.one(
      from(repository in Repository,
        join: subject in Subject,
        on: subject.id == repository.subject_id,
        join: assignment in Assignment,
        on: assignment.id == subject.assignment_id,
        join: classroom in Classroom,
        on: classroom.id == assignment.classroom_id,
        where: repository.github_repository_id == ^github_repository_id,
        select: %{
          repository: repository,
          subject: subject,
          assignment: assignment,
          classroom: classroom
        }
      )
    )
  end

  defp assignment_tests(assignment_id) do
    from(test in AssignmentTest,
      where: test.assignment_id == ^assignment_id,
      order_by: [asc: test.id]
    )
    |> Repo.all()
  end

  defp test_target(%AssignmentTest{} = test) do
    %{
      id: test.id,
      name: test.name,
      description: test.description,
      type: test.type,
      command: test.command,
      path: test.path,
      input: test.input,
      expected: test.expected,
      points: test.points,
      timeout_seconds: test.timeout_seconds
    }
  end

  defp latest_by_subject(schema, subject_ids, order_by, preload \\ nil) do
    query =
      from(record in schema,
        where: record.subject_id in ^subject_ids,
        distinct: record.subject_id,
        order_by: ^order_by
      )

    query = if preload, do: preload(query, ^preload), else: query
    query |> Repo.all() |> Map.new(&{&1.subject_id, &1})
  end

  defp latest_grades_for_latest_pushes(subject_ids) do
    latest_pushes =
      from(push in Push,
        where: push.subject_id in ^subject_ids,
        distinct: push.subject_id,
        order_by: [asc: push.subject_id, desc: push.observed_at, desc: push.id],
        select: %{subject_id: push.subject_id, commit_sha: push.commit_sha}
      )

    from(grade in Grade,
      join: push in subquery(latest_pushes),
      on: push.subject_id == grade.subject_id and push.commit_sha == grade.commit_sha,
      distinct: grade.subject_id,
      order_by: [asc: grade.subject_id, desc: grade.inserted_at, desc: grade.id],
      preload: [:tests]
    )
    |> Repo.all()
    |> Map.new(&{&1.subject_id, &1})
  end

  defp duplicate_delivery(delivery_id, repository_id, commit_sha) do
    case Repo.get_by(Push, delivery_id: delivery_id) do
      %Push{repository_id: ^repository_id, commit_sha: ^commit_sha} = push -> {:ok, push}
      %Push{} -> {:error, :delivery_conflict}
      nil -> {:error, :delivery_conflict}
    end
  end

  defp delivery_conflict?(changeset), do: Keyword.has_key?(changeset.errors, :delivery_id)

  defp valid_observed_at?(%DateTime{time_zone: "Etc/UTC"}), do: true
  defp valid_observed_at?(%DateTime{utc_offset: 0, std_offset: 0}), do: true
  defp valid_observed_at?(_), do: false

  defp utc_microseconds(datetime),
    do: datetime |> DateTime.to_unix(:microsecond) |> DateTime.from_unix!(:microsecond)

  defp validate_commit_sha(sha) when is_binary(sha) do
    if Regex.match?(~r/\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/i, sha),
      do: :ok,
      else: {:error, :invalid_commit_sha}
  end

  defp validate_commit_sha(_), do: {:error, :invalid_commit_sha}

  defp normalize_branch(branch) when is_binary(branch) do
    branch = String.trim(branch)

    if byte_size(branch) <= 255 and not String.contains?(branch, ["\r", "\n", <<0>>]),
      do: branch,
      else: nil
  end

  defp normalize_branch(_), do: nil

  defp decimal(value) do
    case Decimal.cast(value) do
      {:ok, %Decimal{} = decimal} -> {:ok, decimal}
      :error -> {:error, :invalid_score}
    end
  end

  defp decimal_sum(values) do
    values
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
    |> then(&{:ok, &1})
  end

  defp valid_github_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: "github.com"} -> byte_size(url) <= 2_048
      _ -> false
    end
  end

  defp valid_github_url?(_), do: false

  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp field(_, _), do: nil

  defp broadcast_submission(assignment, subject, event) do
    Phoenix.PubSub.broadcast(
      GradePush.PubSub,
      "submission:#{subject.id}",
      {event, subject.id}
    )

    Phoenix.PubSub.broadcast(
      GradePush.PubSub,
      "assignment:#{assignment.id}",
      {event, subject.id}
    )

    if subject.user_id do
      Phoenix.PubSub.broadcast(
        GradePush.PubSub,
        "user:#{subject.user_id}",
        {event, assignment.id}
      )
    end
  end
end
