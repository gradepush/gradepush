defmodule GradePush.ClassroomQueryTest do
  use GradePush.DataCase, async: false

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
    assert large_list_queries == small_list_queries
  end

  defp query_count(fun) do
    ref = make_ref()
    collector = :ets.new(:classroom_query_counts, [:ordered_set, :public])

    :ok =
      :telemetry.attach(
        ref,
        GradePush.Repo.config()[:telemetry_prefix] ++ [:query],
        fn _event, _measurements, _metadata, _config ->
          :ets.insert(collector, {System.unique_integer([:monotonic]), true})
        end,
        nil
      )

    try do
      fun.()
      :ets.info(collector, :size)
    after
      :telemetry.detach(ref)
      :ets.delete(collector)
    end
  end
end
