defmodule GradePush.Demo do
  @moduledoc "Safely seeds and resets a dedicated demo installation."

  import Ecto.Query

  alias GradePush.Accounts

  alias GradePush.Accounts.{
    Institution,
    InstitutionMembership,
    PlatformOperator,
    User,
    UserSession
  }

  alias GradePush.Assignments.{Assignment, AssignmentTest, Repository, Subject, Team, TeamMember}

  alias GradePush.Classrooms.{
    Classroom,
    ClassroomStudent,
    ClassroomTeacher,
    GitHubConnection,
    GitHubConnectionTeacher
  }

  alias GradePush.Crypto
  alias GradePush.Demo.InstanceMode
  alias GradePush.GitHub.Fake
  alias GradePush.GitHub.Fake.Store
  alias GradePush.Installation.GitHubApp
  alias GradePush.Repo
  alias GradePush.Submissions.{Grade, GradeTest, Push}

  @mode_id 1
  @advisory_lock {7_104, 1}
  @bootstrap_table "bootstrap_credentials"
  @instance_tables ~w(
    users institutions institution_memberships platform_operators user_sessions github_apps
    github_user_credentials institution_invitations administrative_audit_events bootstrap_credentials
    github_organization_connections github_connection_teachers classrooms classroom_teachers
    classroom_students classroom_invitations assignments assignment_tests assignment_teams
    assignment_team_members assignment_subjects assignment_invitations assignment_repositories
    submission_pushes autograding_results autograding_test_results github_webhook_deliveries
  )
  @reset_tables @instance_tables
  @github_workers Enum.map(
                    ~w(
                      GradePush.Workers.ProvisionAssignmentRepository
                      GradePush.Workers.SyncAssignmentRepositoryAccess
                      GradePush.Workers.ProcessGitHubDelivery
                    ),
                    & &1
                  )

  @students [
    %{github_id: 9_000_000_101, login: "amelie-fortin", name: "Amélie Fortin", id: "D-1001"},
    %{github_id: 9_000_000_102, login: "maxime-fortin", name: "Maxime Fortin", id: "D-1002"},
    %{github_id: 9_000_000_103, login: "lea-bouchard", name: "Léa Bouchard", id: "D-1003"},
    %{github_id: 9_000_000_104, login: "camille-roy", name: "Camille Roy", id: "D-1004"},
    %{github_id: 9_000_000_105, login: "noah-pelletier", name: "Noah Pelletier", id: "D-1005"},
    %{github_id: 9_000_000_106, login: "thomas-lavoie", name: "Thomas Lavoie", id: "D-1006"},
    %{github_id: 9_000_000_107, login: "maude-gauthier", name: "Maude Gauthier", id: "D-1007"},
    %{github_id: 9_000_000_108, login: "emile-tremblay", name: "Émile Tremblay", id: "D-1008"},
    %{github_id: 9_000_000_109, login: "jade-martel", name: "Jade Martel", id: "D-1009"},
    %{github_id: 9_000_000_110, login: "antoine-morin", name: "Antoine Morin", id: "D-1010"},
    %{github_id: 9_000_000_111, login: "rosalie-gervais", name: "Rosalie Gervais", id: "D-1011"},
    %{github_id: 9_000_000_112, login: "felix-beaulieu", name: "Félix Beaulieu", id: "D-1012"}
  ]

  def enabled? do
    Application.get_env(:gradepush, :demo_mode, false) == true
  end

  def invitation_allowed?, do: not enabled?()

  def ensure_invitations_enabled do
    if invitation_allowed?(), do: :ok, else: {:error, :demo_invitations_disabled}
  end

  def mode do
    case Repo.get(InstanceMode, @mode_id) do
      %InstanceMode{mode: mode} -> mode
      nil -> nil
    end
  end

  def initialize do
    with :ok <- validate_github_adapter(),
         {:ok, :ok} <- initialize_instance() do
      hydrate_demo_repositories()
    end
  end

  def initialize! do
    case initialize() do
      :ok ->
        :ok

      {:error, reason} ->
        raise ArgumentError, "unsafe GradePush instance mode: #{inspect(reason)}"
    end
  end

  def user_for_role(role) when role in [:teacher, :admin, :student] do
    if enabled?() and mode() == :demo do
      login = if role == :student, do: "amelie-fortin", else: "demo-teacher"

      case Repo.get_by(User, login: login) do
        %User{id: user_id} -> {:ok, Accounts.get_user(user_id)}
        nil -> {:error, :demo_not_initialized}
      end
    else
      {:error, :demo_mode_disabled}
    end
  end

  def user_for_role(_role), do: {:error, :invalid_demo_role}

  def reset(opts \\ []) when is_list(opts) do
    cond do
      not enabled?() ->
        {:error, :demo_mode_disabled}

      GradePush.GitHub.adapter() != GradePush.GitHub.Fake ->
        {:error, :demo_requires_fake_github_adapter}

      mode() != :demo ->
        {:error, :demo_instance_required}

      true ->
        reset_demo(opts)
    end
  end

  def reset! do
    reset!([])
  end

  def reset!(opts) when is_list(opts) do
    case reset(opts) do
      :ok -> :ok
      {:error, reason} -> raise ArgumentError, "demo reset refused: #{inspect(reason)}"
    end
  end

  defp initialize_locked!(false, nil) do
    ensure_empty_instance!()
    insert_mode!(:self_hosted)
    :ok
  end

  defp initialize_locked!(false, %InstanceMode{mode: :self_hosted}), do: :ok

  defp initialize_locked!(false, %InstanceMode{mode: :demo}),
    do: Repo.rollback(:demo_database_requires_demo_mode)

  defp initialize_locked!(true, nil) do
    ensure_empty_instance!()
    clear_bootstrap_credentials!()
    insert_mode!(:demo)
    seed_demo!()
    :ok
  end

  defp initialize_locked!(true, %InstanceMode{mode: :self_hosted} = instance) do
    ensure_empty_instance!()
    clear_bootstrap_credentials!()
    instance |> Ecto.Changeset.change(mode: :demo) |> Repo.update!()
    seed_demo!()
    :ok
  end

  defp initialize_locked!(true, %InstanceMode{mode: :demo}), do: seed_demo!()

  defp validate_github_adapter do
    if enabled?() and GradePush.GitHub.adapter() != Fake,
      do: {:error, :demo_requires_fake_github_adapter},
      else: :ok
  end

  defp initialize_instance do
    Repo.transaction(fn ->
      lock_instance!()
      initialize_locked!(enabled?(), locked_mode())
    end)
  end

  defp hydrate_demo_repositories do
    if enabled?() and mode() == :demo, do: hydrate_fake_repositories()
    :ok
  end

  defp locked_mode do
    from(mode in InstanceMode, where: mode.id == ^@mode_id, lock: "FOR UPDATE")
    |> Repo.one()
  end

  defp insert_mode!(mode) do
    %InstanceMode{id: @mode_id}
    |> Ecto.Changeset.change(mode: mode)
    |> Repo.insert!()
  end

  defp lock_instance! do
    {namespace, key} = @advisory_lock
    Repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [namespace, key])
  end

  defp ensure_empty_instance! do
    populated = Enum.filter(@instance_tables -- [@bootstrap_table], &table_has_rows?/1)

    if populated == [] do
      :ok
    else
      Repo.rollback(:demo_requires_empty_installation)
    end
  end

  defp table_has_rows?(table) do
    %{rows: [[has_rows?]]} = Repo.query!("SELECT EXISTS (SELECT 1 FROM #{table} LIMIT 1)")
    has_rows?
  end

  defp clear_bootstrap_credentials! do
    Repo.query!("DELETE FROM bootstrap_credentials")
  end

  defp reset_demo(opts) do
    current_job_id = Keyword.get(opts, :job_id)

    result =
      Repo.transaction(fn ->
        lock_instance!()

        case locked_mode() do
          %InstanceMode{mode: :demo} ->
            Repo.query!("LOCK TABLE users, user_sessions IN ACCESS EXCLUSIVE MODE")
            session_hashes = Repo.all(from(session in UserSession, select: session.token_hash))
            cancel_github_jobs!(current_job_id)
            truncate_demo_data!()
            seed_demo!()
            session_hashes

          %InstanceMode{} ->
            Repo.rollback(:demo_instance_required)

          nil ->
            Repo.rollback(:demo_instance_required)
        end
      end)

    case result do
      {:ok, hashes} ->
        Enum.each(hashes, &Accounts.broadcast_session_revoked/1)
        Fake.reset!()
        hydrate_fake_repositories()
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cancel_github_jobs!(current_job_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    query =
      from(job in Oban.Job,
        where:
          job.worker in ^@github_workers and
            job.state in ["available", "scheduled", "retryable", "executing"]
      )

    query =
      if is_integer(current_job_id),
        do: where(query, [job], job.id != ^current_job_id),
        else: query

    Repo.update_all(query, set: [state: "cancelled", cancelled_at: now])
    :ok
  end

  defp truncate_demo_data! do
    tables = Enum.join(@reset_tables, ", ")
    Repo.query!("TRUNCATE TABLE #{tables} CASCADE")
  end

  defp hydrate_fake_repositories do
    repositories =
      Repo.all(
        from(repository in Repository,
          where:
            not is_nil(repository.github_repository_id) and not is_nil(repository.owner_login) and
              not is_nil(repository.name),
          select: repository
        )
      )

    Enum.each(repositories, fn repository ->
      Store.put(
        {:repository, repository.owner_login, repository.name},
        %{
          "id" => repository.github_repository_id,
          "name" => repository.name,
          "full_name" => repository.full_name,
          "private" => true,
          "html_url" => repository.html_url,
          "owner" => %{"id" => 9_000_000_789, "login" => repository.owner_login}
        }
      )
    end)

    :ok
  end

  defp seed_demo! do
    cond do
      Repo.get_by(User, login: "demo-teacher") && complete_seed?() ->
        :ok

      Enum.any?(@instance_tables -- [@bootstrap_table], &table_has_rows?/1) ->
        Repo.rollback(:demo_data_incomplete)

      true ->
        seed_demo_records!()
    end
  end

  defp complete_seed? do
    institution = Repo.one(Institution)

    institution != nil and
      Repo.exists?(from(classroom in Classroom, where: classroom.slug == "programming")) and
      Repo.exists?(from(classroom in Classroom, where: classroom.slug == "web-development")) and
      Repo.exists?(from(user in User, where: user.login == "amelie-fortin"))
  end

  defp seed_demo_records! do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    institution = insert_institution!()
    teacher = insert_user!(9_000_000_001, "demo-teacher", "Alex Martin", "fr")
    colleague = insert_user!(9_000_000_002, "camille-bergeron", "Camille Bergeron", "fr")
    students = Enum.map(@students, &insert_student!(&1, institution.id, now))

    insert_membership!(institution.id, teacher.id, :admin, now)
    insert_membership!(institution.id, teacher.id, :teacher, now)
    insert_membership!(institution.id, colleague.id, :teacher, now)
    Repo.insert!(%PlatformOperator{user_id: teacher.id, added_by_id: teacher.id})
    insert_github_app!()

    connection = insert_connection!(teacher.id)
    insert_connection_teacher!(connection.id, teacher.id)
    insert_connection_teacher!(connection.id, colleague.id)

    programming =
      insert_classroom!(teacher, connection, %{
        slug: "programming",
        title: "Programmation I",
        code: "420-110",
        description: "Développer une base solide en Python et en résolution de problèmes.",
        semester: "fall",
        academic_year: 2026
      })

    web_development =
      insert_classroom!(teacher, connection, %{
        slug: "web-development",
        title: "Développement Web",
        code: "420-210",
        description: "Créer des expériences Web accessibles et adaptées à tous les écrans.",
        semester: "fall",
        academic_year: 2026
      })

    insert_classroom_teacher!(programming.id, teacher.id)
    insert_classroom_teacher!(programming.id, colleague.id)
    insert_classroom_teacher!(web_development.id, teacher.id)
    insert_students_in_class!(programming.id, Enum.take(students, 8), now)
    insert_students_in_class!(web_development.id, Enum.take(students, 6), now)

    cli =
      insert_assignment!(programming, %{
        slug: "cli",
        title: "Analyseur d’arguments CLI",
        instructions:
          "# Objectif\n\nCréez un analyseur d’arguments en ligne de commande.\n\nDocumentez les cas valides et les erreurs dans votre dépôt.",
        deadline_at: DateTime.add(now, 4 * 86_400, :second),
        template_repository: "gradepush-demo/starter",
        autograding_enabled: true
      })

    loops =
      insert_assignment!(programming, %{
        slug: "loops",
        title: "Boucles et collections",
        instructions: "Écrivez des fonctions pour parcourir et transformer des collections.",
        deadline_at: DateTime.add(now, -9 * 86_400, :second),
        autograding_enabled: false
      })

    functions =
      insert_assignment!(programming, %{
        slug: "functions",
        title: "Fonctions et tests",
        instructions: "En équipe, implémentez et testez une petite bibliothèque de fonctions.",
        deadline_at: DateTime.add(now, 14 * 86_400, :second),
        kind: "team",
        team_mode: "teacher",
        autograding_enabled: false
      })

    portfolio =
      insert_assignment!(web_development, %{
        slug: "portfolio",
        title: "Portfolio adaptatif",
        instructions:
          "Concevez un portfolio accessible qui s’adapte aux petits et grands écrans.",
        deadline_at: DateTime.add(now, 7 * 86_400, :second),
        autograding_enabled: false
      })

    tests = insert_assignment_tests!(cli)
    accepted_cli = Enum.take(students, 5) |> Enum.with_index()
    seed_individual_submissions!(cli, accepted_cli, tests, now, "cli")

    seed_individual_submissions!(
      loops,
      Enum.take(students, 7) |> Enum.with_index(),
      [],
      now,
      "loops"
    )

    seed_team_submissions!(functions, students, teacher.id, now)

    seed_individual_submissions!(
      portfolio,
      Enum.take(students, 4) |> Enum.with_index(),
      [],
      now,
      "portfolio"
    )

    :ok
  end

  defp insert_institution! do
    %Institution{}
    |> Institution.changeset(%{name: "Cégep de Sorel-Tracy"})
    |> Repo.insert!()
  end

  defp insert_user!(github_id, login, name, locale) do
    %User{}
    |> User.changeset(%{github_id: github_id, login: login, name: name, locale: locale})
    |> Repo.insert!()
  end

  defp insert_student!(attrs, institution_id, now) do
    user = insert_user!(attrs.github_id, attrs.login, attrs.name, "fr")
    insert_membership!(institution_id, user.id, :student, now, attrs.name, attrs.id)
    user
  end

  defp insert_membership!(
         institution_id,
         user_id,
         role,
         now,
         student_name \\ nil,
         student_id \\ nil
       ) do
    %InstitutionMembership{}
    |> InstitutionMembership.changeset(%{
      institution_id: institution_id,
      user_id: user_id,
      role: role,
      student_name: student_name,
      student_id: student_id,
      joined_at: now
    })
    |> Repo.insert!()
  end

  defp insert_github_app! do
    {:ok, client_secret} = Crypto.encrypt("demo-client-secret", "github_app.client_secret")
    {:ok, private_key} = Crypto.encrypt("demo-private-key", "github_app.private_key")
    {:ok, webhook_secret} = Crypto.encrypt("demo-webhook-secret", "github_app.webhook_secret")

    %GitHubApp{}
    |> GitHubApp.changeset(%{
      app_id: 456,
      client_id: "demo-client-id",
      client_secret_encrypted: client_secret,
      private_key_encrypted: private_key,
      webhook_secret_encrypted: webhook_secret,
      slug: "gradepush-demo",
      html_url: "https://github.com/apps/gradepush-demo"
    })
    |> Repo.insert!()
  end

  defp insert_connection!(teacher_id) do
    %GitHubConnection{}
    |> GitHubConnection.changeset(%{
      github_organization_id: 9_000_000_789,
      login: "gradepush-demo",
      installation_id: 123,
      sharing_scope: "institution",
      status: "active",
      connected_by_id: teacher_id
    })
    |> Repo.insert!()
  end

  defp insert_connection_teacher!(connection_id, user_id) do
    Repo.insert!(%GitHubConnectionTeacher{connection_id: connection_id, user_id: user_id})
  end

  defp insert_classroom!(teacher, connection, attrs) do
    %Classroom{}
    |> Classroom.changeset(Map.put(attrs, :github_connection_id, connection.id))
    |> Ecto.Changeset.put_change(:created_by_id, teacher.id)
    |> Repo.insert!()
  end

  defp insert_classroom_teacher!(classroom_id, user_id) do
    Repo.insert!(%ClassroomTeacher{classroom_id: classroom_id, user_id: user_id})
  end

  defp insert_students_in_class!(classroom_id, students, now) do
    Enum.each(students, fn student ->
      %ClassroomStudent{classroom_id: classroom_id, user_id: student.id}
      |> ClassroomStudent.changeset(%{joined_at: now})
      |> Repo.insert!()
    end)
  end

  defp insert_assignment!(classroom, attrs) do
    defaults = %{
      kind: "individual",
      team_mode: "students",
      team_size: 2,
      repository_visibility: "private",
      repository_name_pattern: "{classroom}-{assignment}-{identifier}",
      cutoff_enabled: false,
      published_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    }

    attrs = Map.merge(defaults, attrs)

    %Assignment{}
    |> Assignment.changeset(attrs)
    |> Ecto.Changeset.put_change(:classroom_id, classroom.id)
    |> Repo.insert!()
  end

  defp insert_assignment_tests!(assignment) do
    [
      %{
        name: "Parses valid options",
        description: "Recognizes named options and values.",
        type: "command",
        points: 20,
        command: "python -m unittest tests.test_parser"
      },
      %{
        name: "Handles missing values",
        description: "Reports an error for options without a value.",
        type: "io",
        points: 30,
        command: "python main.py",
        input: "--output",
        expected: "missing value"
      },
      %{
        name: "Includes project files",
        description: "Keeps the command-line entry point in the repository.",
        type: "file",
        points: 50,
        path: "main.py"
      }
    ]
    |> Enum.map(fn attrs ->
      %AssignmentTest{assignment_id: assignment.id}
      |> AssignmentTest.changeset(attrs)
      |> Repo.insert!()
    end)
  end

  defp seed_individual_submissions!(assignment, students, tests, now, prefix) do
    Enum.each(students, fn {student, index} ->
      accepted_at = DateTime.add(now, -(index + 4) * 86_400, :second)

      subject =
        %Subject{}
        |> Subject.changeset(%{
          assignment_id: assignment.id,
          user_id: student.id,
          kind: "individual",
          accepted_at: accepted_at
        })
        |> Repo.insert!()

      repository = insert_repository!(subject, prefix, student.login, index)

      maybe_seed_individual_push(
        assignment,
        subject,
        repository,
        tests,
        now,
        prefix,
        student,
        index
      )
    end)
  end

  defp maybe_seed_individual_push(
         _assignment,
         _subject,
         _repository,
         _tests,
         _now,
         _prefix,
         _student,
         3
       ),
       do: :ok

  defp maybe_seed_individual_push(
         assignment,
         subject,
         repository,
         tests,
         now,
         prefix,
         student,
         index
       ) do
    pushed_at = DateTime.add(now, -(index + 1) * 86_400 + 60 * 60, :second)
    sha = commit_sha(prefix, student.login, index)
    insert_push!(subject, repository, sha, pushed_at, prefix, index)
    maybe_seed_grade(assignment, subject, repository, tests, sha, index)
  end

  defp maybe_seed_grade(assignment, subject, repository, tests, sha, index)
       when tests != [] and index in [0, 2] do
    score = if index == 0, do: 100, else: 70
    insert_grade!(assignment, subject, repository, tests, sha, score, 800_000 + index)
  end

  defp maybe_seed_grade(_assignment, _subject, _repository, _tests, _sha, _index), do: :ok

  defp seed_team_submissions!(assignment, students, teacher_id, now) do
    students
    |> Enum.take(8)
    |> Enum.chunk_every(2)
    |> Enum.with_index(1)
    |> Enum.each(fn {members, index} ->
      team =
        %Team{}
        |> Team.changeset(%{
          assignment_id: assignment.id,
          created_by_id: teacher_id,
          name: "Équipe #{index}"
        })
        |> Repo.insert!()

      Enum.each(members, fn student ->
        Repo.insert!(%TeamMember{
          assignment_id: assignment.id,
          team_id: team.id,
          user_id: student.id
        })
      end)

      subject =
        %Subject{}
        |> Subject.changeset(%{
          assignment_id: assignment.id,
          team_id: team.id,
          kind: "team",
          accepted_at: DateTime.add(now, -index * 86_400, :second)
        })
        |> Repo.insert!()

      repository = insert_repository!(subject, "functions", "team-#{index}", index)
      pushed_at = DateTime.add(now, -(index + 1) * 86_400 + 90 * 60, :second)

      insert_push!(
        subject,
        repository,
        commit_sha("functions", "team-#{index}", index),
        pushed_at,
        "functions",
        index
      )
    end)
  end

  defp insert_repository!(subject, prefix, login, index) do
    name = "#{prefix}-#{String.replace(login, "_", "-")}"

    %Repository{subject_id: subject.id}
    |> Repository.changeset(%{
      github_repository_id: 9_100_000_000 + subject.id,
      owner_login: "gradepush-demo",
      name: name,
      full_name: "gradepush-demo/#{name}",
      html_url: "https://github.com/gradepush-demo/#{name}",
      workflow_id: if(prefix == "cli", do: 123_400 + index, else: nil),
      workflow_path: if(prefix == "cli", do: ".github/workflows/gradepush.yml", else: nil),
      workflow_file_sha: if(prefix == "cli", do: String.duplicate("d", 40), else: nil),
      state: "ready"
    })
    |> Repo.insert!()
  end

  defp insert_push!(subject, repository, sha, pushed_at, prefix, index) do
    %Push{}
    |> Push.changeset(%{
      subject_id: subject.id,
      repository_id: repository.id,
      commit_sha: sha,
      branch: "main",
      observed_at: pushed_at,
      delivery_id: "demo-#{prefix}-#{index}-#{subject.id}"
    })
    |> Repo.insert!()
  end

  defp insert_grade!(assignment, subject, repository, tests, sha, score, run_id) do
    grade =
      %Grade{}
      |> Grade.changeset(%{
        subject_id: subject.id,
        repository_id: repository.id,
        commit_sha: sha,
        run_id: run_id,
        status: "success",
        score: Decimal.new(score),
        max_score: Decimal.new(100),
        html_url: repository.html_url <> "/actions/runs/#{run_id}"
      })
      |> Repo.insert!()

    Enum.each(tests, fn test ->
      points = Decimal.new(test.points)
      awarded = if score == 100, do: points, else: Decimal.mult(points, Decimal.new("0.7"))

      %GradeTest{result_id: grade.id, assignment_test_id: test.id}
      |> GradeTest.changeset(%{
        name: test.name,
        status: if(awarded == points, do: "success", else: "failure"),
        points_awarded: awarded,
        max_points: points
      })
      |> Repo.insert!()
    end)

    assignment
  end

  defp commit_sha(prefix, login, index) do
    :crypto.hash(:sha, "#{prefix}:#{login}:#{index}") |> Base.encode16(case: :lower)
  end
end
