defmodule OpenTrackWeb.FoodAnalysisLiveTest do
  use OpenTrackWeb.ConnCase
  import Phoenix.LiveViewTest
  import OpenTrack.Fixtures
  import OpenTrack.AnalysisFixtures
  alias OpenTrack.FakeReqLLM
  alias OpenTrack.Food

  @moduletag :capture_log

  setup %{conn: conn} do
    configure_ai()
    owner = user()
    %{conn: log_in(conn, owner), owner: owner}
  end

  test "upload disclosure and persisted analysis appear after refreshing the page", %{
    conn: conn,
    owner: owner
  } do
    stub_prediction()
    {:ok, view, _} = live(conn, "/app/add")
    assert has_element?(view, "#food-ai-notice", "OpenRouter")
    assert has_element?(view, "#food-ai-notice", "google/gemini-3.1-flash-lite")
    assert has_element?(view, "#food-ai-notice", "embedded metadata")
    save_photo(view)
    assert_patch(view, "/app/journal")
    [photo] = Food.list_food_photos!(owner.id, page: [limit: 24]).results
    assert has_element?(view, "#photos-#{photo.id}[data-analysis-status='not_analyzed']")

    assert %{success: 1} = drain_analysis()
    assert_analysis(photo.id, owner, :completed)

    assert has_element?(view, "#photos-#{photo.id}[data-analysis-status='not_analyzed']")
    refute has_element?(view, "#calories-chart-values tbody tr")
    {:ok, view, _} = live(conn, "/app/journal")
    assert has_element?(view, "#photos-#{photo.id}[data-analysis-status='completed']")
    assert has_element?(view, "#photos-#{photo.id}", "520 kcal")
    assert has_element?(view, "#photos-#{photo.id}-analysis:not([open])", "AI food details")
    assert has_element?(view, "#food_log-#{photo.id}", "520 kcal")
    assert has_element?(view, "#food_log-#{photo.id}", "32 g protein")
    assert has_element?(view, "#calories-chart-values tbody td", "520")
    assert has_element?(view, "#protein-chart-values tbody td", "32.0")
    refute has_element?(view, "#weight-chart .chart-point")
    assert has_element?(view, "#calories-chart", "Not measured intake")
  end

  test "uploads and disclosure use the fixed model", %{conn: conn, owner: owner} do
    {:ok, view, _} = live(conn, "/app/add")
    assert has_element?(view, "#food-ai-notice", "google/gemini-3.1-flash-lite")
    parent = self()

    FakeReqLLM.stub(fn model, _context, _schema, _opts ->
      send(parent, {:model, model})
      response()
    end)

    save_photo(view)
    [photo] = Food.list_food_photos!(owner.id, page: [limit: 24]).results
    assert %{success: 1} = drain_analysis()
    assert_analysis(photo.id, owner, :completed)
    assert_receive {:model, "openrouter:google/gemini-3.1-flash-lite"}
  end

  test "closing the page does not cancel queued analysis", %{conn: conn, owner: owner} do
    stub_prediction()
    {:ok, view, _} = live(conn, "/app/add")
    save_photo(view)
    [photo] = Food.list_food_photos!(owner.id, page: [limit: 24]).results
    GenServer.stop(view.pid, :normal)

    assert %{success: 1} = drain_analysis()
    assert_analysis(photo.id, owner, :completed)
    {:ok, reloaded, _} = live(conn, "/app/journal")
    assert has_element?(reloaded, "#photos-#{photo.id}", "520 kcal")
  end

  test "refreshed results paginate normally and escape model descriptions", %{
    conn: conn,
    owner: owner
  } do
    file = upload()
    for _ <- 1..49, do: create_unanalyzed_photo(owner, file)
    {:ok, view, _} = live(conn, "/app/journal")
    view |> element("#load-more") |> render_click()
    ids = card_ids(view)
    assert length(ids) == 48
    id = List.last(ids) |> String.replace_prefix("photos-", "")
    stub_prediction(prediction(%{"description" => "<script>alert('bad')</script>"}))

    assert %{success: 49} = drain_analysis()
    assert_analysis(id, owner, :completed)
    assert has_element?(view, "#photos-#{id}[data-analysis-status='not_analyzed']")
    {:ok, view, _} = live(conn, "/app/journal")
    view |> element("#load-more") |> render_click()
    assert has_element?(view, "#photos-#{id}[data-analysis-status='completed']")
    assert card_ids(view) == ids
    refute has_element?(view, "#photos-#{id} script")
    assert has_element?(view, "#photos-#{id}-analysis p", "<script>alert('bad')</script>")
    assert has_element?(view, "#load-more")
    view |> element("#load-more") |> render_click()
    assert length(card_ids(view)) == 49
    assert has_element?(view, "#photo-count", "49")
  end

  test "deletion updates the current tab; other tabs update after refresh", %{
    conn: conn,
    owner: owner
  } do
    stub_prediction()
    photo = create_analyzed_photo(owner)
    assert photo.analysis_status == :completed
    {:ok, view, _} = live(conn, "/app/journal")
    {:ok, other_tab, _} = live(conn, "/app/journal")
    view |> element("#photos-#{photo.id} button[phx-click='delete-photo']") |> render_click()
    refute has_element?(view, "#photos-#{photo.id}")
    assert has_element?(other_tab, "#photos-#{photo.id}")
    {:ok, other_tab, _} = live(conn, "/app/journal")

    for tab <- [view, other_tab] do
      assert has_element?(tab, "#photo-count", "0")
      refute has_element?(tab, "#calories-chart-values tbody tr")
      refute has_element?(tab, "#food_log-#{photo.id}")
    end
  end

  test "failure and non-food states never fabricate nutrition", %{conn: conn, owner: owner} do
    FakeReqLLM.stub(fn _, _, _, _ -> {:error, "private-provider-error"} end)
    failed = create_analyzed_photo(owner)
    assert failed.analysis_status == :failed

    stub_prediction(
      prediction(%{
        "food_detected" => false,
        "description" => "No food visible.",
        "total_calories" => 0,
        "total_protein_g" => 0,
        "total_mass_g" => 0,
        "ingredients" => []
      })
    )

    nonfood = create_analyzed_photo(owner)
    assert nonfood.analysis_status == :completed
    {:ok, view, _} = live(conn, "/app/journal")
    assert has_element?(view, "#photos-#{failed.id}", "Analysis failed")
    assert has_element?(view, "#photos-#{nonfood.id}", "No food identified")
    refute has_element?(view, "#photos-#{nonfood.id}", "0 kcal")
    refute has_element?(view, "#food_log-#{nonfood.id}", "protein")
    refute has_element?(view, "#photos-#{failed.id}", "private-provider-error")
    refute has_element?(view, "#calories-chart-values tbody tr")
    refute has_element?(view, "#protein-chart-values tbody tr")
  end

  defp save_photo(view) do
    file =
      file_input(view, "#photo-form", :photo, [
        %{name: "lunch.png", content: image_bytes(), type: "image/png"}
      ])

    render_upload(file, "lunch.png")
    view |> form("#photo-form") |> render_submit()
  end

  defp card_ids(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#photos article")
    |> LazyHTML.attribute("id")
  end
end
