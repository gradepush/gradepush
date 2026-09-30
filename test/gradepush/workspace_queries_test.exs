defmodule GradePush.WorkspaceQueriesTest do
  use GradePush.DataCase, async: false

  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures

  alias GradePush.{Accounts, Assignments, Classrooms, Repo}
  alias GradePush.Accounts.InstitutionMembership
  alias GradePush.Classrooms.ClassroomStudent

  setup do
    %{user: teacher} = bootstrap_fixture()
    classroom = classroom_fixture(teacher)
    assignment = assignment_fixture(teacher, classroom)
    %{teacher: teacher, classroom: classroom, assignment: assignment}
  end

  test "role checks use one query and observe revoked persisted roles", %{teacher: teacher} do
    assert {true, [_]} = queries(fn -> Accounts.teacher?(teacher) end)
    Repo.delete_all(from(m in InstitutionMembership, where: m.user_id == ^teacher.id))
    assert {false, [_]} = queries(fn -> Accounts.teacher?(teacher) end)
    assert Accounts.institution_roles(teacher) == []
  end

  test "assignment saves avoid classroom summaries and duplicate App reads", context do
    %{teacher: teacher, assignment: assignment} = context

    assert {{:ok, updated}, sql} =
             queries(fn ->
               Assignments.update_assignment(teacher, assignment.id, %{
                 title: "Updated title",
                 template_repository: "gradepush-test/starter"
               })
             end)

    assert updated.title == "Updated title"
    assert length(sql) <= 20
    assert Enum.count(sql, &(&1.source == "github_apps")) == 1
    refute Enum.any?(sql, &(&1.source == "classroom_students"))
    assert Enum.count(sql, &String.contains?(&1.query, "FOR UPDATE")) == 1

    assert {{:ok, _}, sql} =
             queries(fn ->
               Assignments.update_assignment(teacher, assignment.id, %{template_repository: ""})
             end)

    assert length(sql) <= 17
  end

  test "teacher workspace shares class summaries and keeps actor and archive scopes", context do
    %{teacher: teacher, classroom: classroom} = context
    other = user_fixture()
    teacher_membership_fixture(other)
    other_classroom = classroom_fixture(other)

    assert {{:ok, workspace}, sql} =
             queries(fn -> Classrooms.teacher_workspace(teacher, classroom.slug) end)

    assert Enum.map(workspace.classes, & &1.id) == [classroom.id]
    assert workspace.classroom.id == classroom.id
    assert workspace.students == []
    assert length(workspace.connections) == 1
    assert length(sql) <= 13
    assert Enum.count(sql, &(&1.source == "classroom_students")) == 2

    assert {:ok, %{classroom: nil, students: []}} =
             Classrooms.teacher_workspace(teacher, other_classroom.slug)

    assert {:ok, _} = Classrooms.archive_classroom(teacher, classroom.id)

    assert {:ok, %{classes: [], classroom: selected}} =
             Classrooms.teacher_workspace(teacher, classroom.slug)

    assert selected.id == classroom.id

    Repo.delete_all(
      from(t in GradePush.Classrooms.ClassroomTeacher,
        where: t.classroom_id == ^classroom.id and t.user_id == ^teacher.id
      )
    )

    assert {:ok, %{classroom: nil, students: []}} =
             Classrooms.teacher_workspace(teacher, classroom.slug)

    Repo.delete_all(from(m in InstitutionMembership, where: m.user_id == ^teacher.id))
    assert {:error, :unauthorized} = Classrooms.teacher_workspace(teacher, classroom.slug)
    assert {:error, _} = Classrooms.classroom_for_teacher(teacher, classroom.id)
  end

  test "teacher workspace query count stays constant as the classroom list grows", context do
    %{teacher: teacher, classroom: classroom} = context
    {{:ok, _}, small} = queries(fn -> Classrooms.teacher_workspace(teacher, classroom.slug) end)

    for _ <- 1..12, do: classroom_fixture(teacher)

    {{:ok, workspace}, large} =
      queries(fn -> Classrooms.teacher_workspace(teacher, classroom.slug) end)

    assert length(workspace.classes) == 13
    assert length(large) == length(small)
  end

  test "student workspace reads the selected submission once and stays scoped on every load",
       context do
    %{teacher: teacher, classroom: classroom, assignment: assignment} = context
    student = student_fixture()
    other_student = student_fixture()
    now = DateTime.utc_now()

    for user <- [student, other_student] do
      Repo.insert!(%ClassroomStudent{
        classroom_id: classroom.id,
        user_id: user.id,
        joined_at: now
      })

      Repo.insert!(%GradePush.Assignments.Subject{
        assignment_id: assignment.id,
        user_id: user.id,
        kind: "individual",
        accepted_at: now
      })
    end

    unpublished = assignment_fixture(teacher, classroom)
    Repo.update!(Ecto.Changeset.change(unpublished, published_at: nil))
    foreign_class = classroom_fixture(teacher)
    foreign_assignment = assignment_fixture(teacher, foreign_class)

    assert {{:ok, workspace}, sql} =
             queries(fn ->
               Assignments.student_classroom_workspace(student, classroom.slug, assignment.slug)
             end)

    assert workspace.classroom.id == classroom.id
    assert length(workspace.assignments) == 1
    assert workspace.details == hd(workspace.assignments)
    assert workspace.details.subject.user_id == student.id
    assert Enum.count(sql, &(&1.source == "assignment_subjects")) == 1
    assert length(sql) <= 20

    for slug <- [nil, "missing", unpublished.slug, foreign_assignment.slug] do
      assert {:ok, %{details: %{assignment: nil, subject: nil}}} =
               Assignments.student_classroom_workspace(student, classroom.slug, slug)
    end

    assert {:error, _} =
             Assignments.student_classroom_workspace(student, foreign_class.slug, assignment.slug)

    assert {:error, _} =
             Assignments.student_classroom_workspace(teacher, classroom.slug, assignment.slug)

    assert {:ok, _} = Classrooms.remove_student(teacher, classroom.id, student.id)

    assert {:error, _} =
             Assignments.student_classroom_workspace(student, classroom.slug, assignment.slug)
  end

  defp queries(fun) do
    ref = make_ref()
    collector = :ets.new(:workspace_queries, [:ordered_set, :public])

    :ok =
      :telemetry.attach(
        ref,
        Repo.config()[:telemetry_prefix] ++ [:query],
        fn _, _, metadata, _ ->
          :ets.insert(
            collector,
            {System.unique_integer([:monotonic]),
             %{query: metadata.query, source: metadata.source}}
          )
        end,
        nil
      )

    try do
      result = fun.()
      {result, Enum.map(:ets.tab2list(collector), &elem(&1, 1))}
    after
      :telemetry.detach(ref)
      :ets.delete(collector)
    end
  end
end
