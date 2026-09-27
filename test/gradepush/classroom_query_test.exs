defmodule GradePush.ClassroomQueryTest do
  use GradePush.DataCase, async: true

  import GradePush.AccountsFixtures
  import GradePush.TeachingFixtures

  alias GradePush.Classrooms

  test "classroom summaries batch teacher and assignment counts as the list grows" do
    %{user: teacher} = bootstrap_fixture()
    classroom_fixture(teacher)

    small_list_queries =
      query_count(fn -> assert {:ok, [_]} = Classrooms.list_classrooms(teacher) end)

    for _ <- 1..12, do: classroom_fixture(teacher)

    large_list_queries =
      query_count(fn ->
        assert {:ok, classrooms} = Classrooms.list_classrooms(teacher)
        assert length(classrooms) == 13
      end)

    assert small_list_queries > 0
    assert large_list_queries <= small_list_queries + 2
  end

  defp query_count(fun) do
    ref = make_ref()
    caller = self()

    :ok =
      :telemetry.attach(
        ref,
        GradePush.Repo.config()[:telemetry_prefix] ++ [:query],
        fn _event, _measurements, _metadata, _config ->
          if self() == caller, do: send(caller, {ref, :query})
        end,
        nil
      )

    try do
      fun.()
      count_messages(ref, 0)
    after
      :telemetry.detach(ref)
    end
  end

  defp count_messages(ref, count) do
    receive do
      {^ref, :query} -> count_messages(ref, count + 1)
    after
      0 -> count
    end
  end
end
