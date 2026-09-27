defmodule OpenTrackWeb.NutritionChart do
  @moduledoc "Presentation-only geometry for dated measurements. Never fabricates values."

  @metrics [
    %{
      key: :calories,
      title: "Calories",
      unit: "kcal",
      icon: "hero-fire",
      kind: :bar,
      precision: 0
    },
    %{key: :protein, title: "Protein", unit: "g", icon: "hero-bolt", kind: :bar, precision: 1},
    %{key: :weight, title: "Weight", unit: "kg", icon: "hero-scale", kind: :line, precision: 1},
    %{
      key: :steps,
      title: "Steps",
      unit: "steps",
      icon: "hero-arrow-trending-up",
      kind: :line,
      precision: 0
    },
    %{
      key: :body_fat,
      title: "Body fat",
      unit: "%",
      icon: "hero-chart-pie",
      kind: :line,
      precision: 1
    }
  ]

  def metrics, do: @metrics
  def days(value) when value in ["7", "30", "90"], do: String.to_integer(value)
  def days(_), do: 7

  def format(nil, _), do: "Not recorded"
  def format(value, 0), do: value |> round() |> Integer.to_string()
  def format(value, 1), do: :erlang.float_to_binary(value / 1, decimals: 1)

  def plot(metric, entries, days, today) do
    first_date = Date.add(today, 1 - days)

    values =
      entries
      |> Enum.filter(
        &(Date.compare(&1.date, first_date) != :lt and Date.compare(&1.date, today) != :gt)
      )
      |> Enum.filter(&(not is_nil(Map.get(&1, metric.key))))
      |> Enum.sort_by(& &1.date, Date)
      |> Enum.map(&%{date: &1.date, value: Map.fetch!(&1, metric.key)})

    width = max(340, days * 24 + 60)
    step = (width - 64) / days
    ceiling = max(1, Enum.reduce(values, 0, &max(&1.value, &2)) * 1.15)
    y = fn value -> 156 - value / ceiling * 132 end

    points =
      Enum.map(values, fn entry ->
        Map.merge(entry, %{
          x: 46 + step * (Date.diff(entry.date, first_date) + 0.5),
          y: y.(entry.value),
          width: min(step * 0.56, 24)
        })
      end)

    %{
      width: width,
      points: points,
      segments:
        points
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.filter(fn [a, b] -> Date.diff(b.date, a.date) == 1 end),
      average: if(values != [], do: Enum.sum(Enum.map(values, & &1.value)) / length(values)),
      ticks:
        for(fraction <- [0, 0.5, 1], do: %{value: ceiling * fraction, y: y.(ceiling * fraction)}),
      first_date: first_date,
      last_date: today
    }
  end
end
