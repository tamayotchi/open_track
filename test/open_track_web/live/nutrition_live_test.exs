defmodule OpenTrackWeb.NutritionLiveTest do
  use OpenTrackWeb.ConnCase
  import Phoenix.LiveViewTest
  import OpenTrack.Fixtures
  import OpenTrack.AnalysisFixtures
  alias OpenTrack.Accounts
  alias OpenTrackWeb.NutritionChart

  setup %{conn: conn} do
    owner = user()
    %{conn: log_in(conn, owner), owner: owner}
  end

  test "the journal keeps all graphs without fabricating measurements", %{conn: conn} do
    {:ok, view, _} = live(conn, "/app")

    for metric <- NutritionChart.metrics() do
      assert has_element?(view, "##{metric.key}-chart svg[role='img']")
      assert has_element?(view, "##{metric.key}-chart", "Not recorded")
      refute has_element?(view, "##{metric.key}-chart-values tbody tr")

      refute has_element?(
               view,
               "##{metric.key}-chart .chart-bar, ##{metric.key}-chart .chart-point"
             )
    end
  end

  test "charts sum owned food estimates by UTC upload date without filling missing days", %{
    conn: conn,
    owner: owner
  } do
    today = Date.utc_today()
    midnight = DateTime.new!(today, ~T[00:00:00], "Etc/UTC")
    first = DateTime.add(midnight, -6, :day)
    yesterday = DateTime.add(midnight, -1, :day)

    for {actor, status, timestamp} <- [
          {owner, :completed, midnight},
          {owner, :completed, DateTime.add(midnight, 86_399, :second)},
          {owner, :completed, first},
          {owner, :failed, yesterday},
          {owner, :not_analyzed, yesterday},
          {owner, :completed, DateTime.add(midnight, 1, :day)},
          {owner, :completed, DateTime.add(first, -1, :second)},
          {user(), :completed, midnight}
        ] do
      nutrition_photo(actor, timestamp, %{analysis_status: status})
    end

    nutrition_photo(owner, yesterday, %{
      analysis:
        prediction(%{
          "food_detected" => false,
          "total_calories" => 0,
          "total_protein_g" => 0,
          "total_mass_g" => 0,
          "ingredients" => []
        })
    })

    {:ok, view, _} = live(conn, "/app")
    first_label = Calendar.strftime(first, "%b %-d, %Y")
    today_label = Calendar.strftime(today, "%b %-d, %Y")

    assert chart_values(view, :calories) == [{first_label, "520"}, {today_label, "1040"}]
    assert chart_values(view, :protein) == [{first_label, "32.0"}, {today_label, "64.0"}]
  end

  test "chart totals include photos beyond the visible journal page", %{conn: conn, owner: owner} do
    today = Date.utc_today()
    timestamp = DateTime.new!(today, ~T[12:00:00], "Etc/UTC")
    for _ <- 1..25, do: nutrition_photo(owner, timestamp)

    {:ok, view, _} = live(conn, "/app")
    assert has_element?(view, "#photos article:nth-of-type(24)")
    refute has_element?(view, "#photos article:nth-of-type(25)")
    date_label = Calendar.strftime(today, "%b %-d, %Y")
    assert chart_values(view, :calories) == [{date_label, "13000"}]
    assert chart_values(view, :protein) == [{date_label, "800.0"}]

    view |> element("#load-more") |> render_click()
    assert has_element?(view, "#photos article:nth-of-type(25)")
    assert chart_values(view, :calories) == [{date_label, "13000"}]
    assert chart_values(view, :protein) == [{date_label, "800.0"}]
  end

  test "range selection updates the charts without losing persisted targets", %{
    conn: conn,
    owner: owner
  } do
    Accounts.create_settings!(%{target_weight_kg: 72}, actor: owner)
    today = Date.utc_today()

    for offset <- [0, -7, -30, -90] do
      timestamp = DateTime.new!(Date.add(today, offset), ~T[12:00:00], "Etc/UTC")
      nutrition_photo(owner, timestamp)
    end

    {:ok, view, _} = live(conn, "/app")
    assert has_element?(view, "#targets-summary", "72")

    for {days, offsets} <- [{"7", [0]}, {"30", [-7, 0]}, {"90", [-30, -7, 0]}] do
      view |> form("#chart-range", days: days) |> render_change()

      for metric <- NutritionChart.metrics() do
        assert has_element?(view, "##{metric.key}-chart .sample-week", "Last #{days} days")
      end

      assert chart_values(view, :calories) ==
               Enum.map(offsets, fn offset ->
                 {Calendar.strftime(Date.add(today, offset), "%b %-d, %Y"), "520"}
               end)
    end

    render_change(view, "range", %{"days" => "7000"})
    assert has_element?(view, "#calories-chart .sample-week", "Last 7 days")
    assert chart_values(view, :calories) == [{Calendar.strftime(today, "%b %-d, %Y"), "520"}]
    assert has_element?(view, "#targets-summary", "72")
  end

  defp nutrition_photo(owner, timestamp, attrs \\ %{}) do
    create_unanalyzed_photo(owner)
    |> Ash.Seed.update!(
      Map.merge(
        %{analysis_status: :completed, analysis: prediction(), inserted_at: timestamp},
        attrs
      )
    )
  end

  defp chart_values(view, metric) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("##{metric}-chart-values tbody tr")
    |> Enum.map(fn row ->
      {row |> LazyHTML.query("th") |> LazyHTML.text() |> String.trim(),
       row |> LazyHTML.query("td") |> LazyHTML.text() |> String.trim()}
    end)
  end
end
