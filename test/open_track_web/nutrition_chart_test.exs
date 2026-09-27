defmodule OpenTrackWeb.NutritionChartTest do
  use ExUnit.Case, async: true
  alias OpenTrackWeb.NutritionChart

  test "empty histories never invent data or divide by zero" do
    for metric <- NutritionChart.metrics(), days <- [7, 30, 90] do
      plot = NutritionChart.plot(metric, [], days, ~D[2026-09-20])
      assert plot.points == []
      assert plot.segments == []
      assert is_nil(plot.average)
      assert plot.last_date == ~D[2026-09-20]
      assert Date.diff(plot.last_date, plot.first_date) == days - 1
    end
  end

  test "geometry fits actual values; missing days are not zero and line gaps stay gaps" do
    for metric <- NutritionChart.metrics() do
      entries =
        for {date, value} <- [
              {~D[2026-09-15], 5000},
              {~D[2026-09-16], 0},
              {~D[2026-09-17], nil},
              {~D[2026-09-19], 7000}
            ],
            do: Map.put(%{date: date}, metric.key, value)

      plot = NutritionChart.plot(metric, entries, 7, ~D[2026-09-20])
      assert [first, zero, last] = plot.points

      assert Enum.map(plot.points, &{&1.date, &1.value}) == [
               {~D[2026-09-15], 5000},
               {~D[2026-09-16], 0},
               {~D[2026-09-19], 7000}
             ]

      assert plot.segments == [[first, zero]]
      assert zero.y == 156
      assert last.y < first.y
      assert first.x < zero.x and zero.x < last.x
      assert_in_delta plot.average, 4000, 0.001

      assert Enum.all?(
               plot.points,
               &(&1.y >= 24 and &1.y <= 156 and &1.x > 0 and &1.x < plot.width)
             )
    end
  end

  test "ranges exclude dates outside the requested period and reject unbounded inputs" do
    metric = hd(NutritionChart.metrics())

    entries = [
      %{date: ~D[2026-09-20], calories: 2000},
      %{date: ~D[2026-09-13], calories: 1000},
      %{date: ~D[2026-09-14], calories: 1500},
      %{date: ~D[2026-09-21], calories: 3000}
    ]

    week = NutritionChart.plot(metric, entries, 7, ~D[2026-09-20])
    month = NutritionChart.plot(metric, entries, 30, ~D[2026-09-20])
    assert Enum.map(week.points, & &1.date) == [~D[2026-09-14], ~D[2026-09-20]]
    assert Enum.map(month.points, & &1.date) == [~D[2026-09-13], ~D[2026-09-14], ~D[2026-09-20]]
    assert NutritionChart.days("7") == 7
    assert NutritionChart.days("30") == 30
    assert NutritionChart.days("90") == 90
    for value <- [nil, "", "-1", "7000", %{}], do: assert(NutritionChart.days(value) == 7)
  end
end
