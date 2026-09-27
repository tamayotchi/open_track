defmodule OpenTrackWeb.NutritionLiveTest do
  use OpenTrackWeb.ConnCase
  import Phoenix.LiveViewTest
  import OpenTrack.Fixtures
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

  test "range selection updates the charts without losing persisted targets", %{
    conn: conn,
    owner: owner
  } do
    Accounts.create_settings!(%{target_weight_kg: 72}, actor: owner)
    {:ok, view, _} = live(conn, "/app")
    assert has_element?(view, "#targets-summary", "72")

    view |> form("#chart-range", days: "30") |> render_change()

    for metric <- NutritionChart.metrics() do
      assert has_element?(view, "##{metric.key}-chart .sample-week", "Last 30 days")
    end

    render_change(view, "range", %{"days" => "7000"})
    assert has_element?(view, "#calories-chart .sample-week", "Last 7 days")
    assert has_element?(view, "#targets-summary", "72")
  end
end
