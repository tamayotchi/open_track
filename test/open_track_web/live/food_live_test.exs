defmodule OpenTrackWeb.FoodLiveTest do
  use OpenTrackWeb.ConnCase
  import Phoenix.LiveViewTest
  import OpenTrack.Fixtures
  import OpenTrack.AnalysisFixtures
  alias OpenTrack.Food

  setup %{conn: conn} do
    configure_ai()
    owner = user()
    %{conn: log_in(conn, owner), owner: owner}
  end

  test "empty journal and card/table switch", %{conn: conn} do
    {:ok, view, _} = live(conn, "/app")
    assert has_element?(view, "#nav-home[aria-current='page']")
    assert has_element?(view, "#photos[phx-update='stream']:not([hidden])")
    assert has_element?(view, "#empty-journal")
    assert has_element?(view, "#photo-count", "0")
    view |> element("#view-table") |> render_click()
    assert has_element?(view, "#photos[hidden]")
    assert has_element?(view, "#food-log-panel:not([hidden])")
    view |> element("#view-cards") |> render_click()
    assert has_element?(view, "#photos:not([hidden])")
    render_click(view, "set-view", %{"mode" => "invalid"})
    assert has_element?(view, "#view-cards[aria-pressed='true']")
  end

  test "uploads persist across remounts and can be deleted", %{conn: conn, owner: owner} do
    {:ok, view, _} = live(conn, "/app/add")

    upload =
      file_input(view, "#photo-form", :photo, [
        %{name: "lunch.png", content: image_bytes(), type: "image/png"}
      ])

    render_upload(upload, "lunch.png")
    view |> form("#photo-form") |> render_submit()
    assert_patch(view, "/app")
    assert has_element?(view, "#photo-count", "1")

    assert [photo] =
             Food.list_food_photos!(actor: owner, page: [limit: 24], load: :image_url).results

    await_photo(photo.id, owner, :failed)
    assert is_binary(photo.image_url)
    assert has_element?(view, "#photos-#{photo.id} img[src='#{photo.image_url}']")
    {:ok, reloaded, _} = live(conn, "/app")
    assert has_element?(reloaded, "#photos-#{photo.id} img[src='#{photo.image_url}']")
    assert has_element?(reloaded, "#food_log-#{photo.id} img[src='#{photo.image_url}']")
    reloaded |> element("#photos-#{photo.id} button[phx-click='delete-photo']") |> render_click()
    refute has_element?(reloaded, "#photos-#{photo.id}")
    refute has_element?(reloaded, "#food_log-#{photo.id}")
    assert has_element?(reloaded, "#photo-count", "0")
    assert has_element?(reloaded, "#empty-journal")
    assert Food.list_food_photos!(actor: owner, page: [limit: 24]).results == []
  end

  test "another user's photos stay hidden and forged deletion events fail", %{conn: conn} do
    other = user()
    photo = create_unanalyzed_photo(other)
    {:ok, view, _} = live(conn, "/app")
    refute has_element?(view, "#photos-#{photo.id}")
    refute has_element?(view, "#food_log-#{photo.id}")
    assert has_element?(view, "#photo-count", "0")

    render_click(view, "delete-photo", %{"id" => photo.id})
    assert has_element?(view, "#flash-error", "Could not delete this photo.")
    assert Food.get_food_photo!(photo.id, actor: other).id == photo.id
  end

  test "unknown and malformed photo IDs show a deletion error without crashing", %{conn: conn} do
    {:ok, view, _} = live(conn, "/app")

    for id <- [Ash.UUID.generate(), "not-a-uuid"] do
      render_click(view, "delete-photo", %{"id" => id})
      assert has_element?(view, "#flash-error", "Could not delete this photo.")
      assert has_element?(view, "#photos")
    end
  end

  test "selection can be cancelled and incomplete uploads cannot be submitted", %{conn: conn} do
    {:ok, view, _} = live(conn, "/app/add")
    render_submit(view, "save-photo", %{})
    assert has_element?(view, "#flash-error")

    upload =
      file_input(view, "#photo-form", :photo, [
        %{name: "lunch.png", content: image_bytes(), type: "image/png"}
      ])

    assert {:ok, _} = preflight_upload(upload)
    assert has_element?(view, ".upload-preview")
    render_submit(view, "save-photo", %{})
    assert has_element?(view, "#photo-count", "0")
    view |> element("button[phx-click='cancel-upload']") |> render_click()
    refute has_element?(view, ".upload-preview")
  end

  test "LiveView rejects large and unsupported files without saving a photo", %{
    conn: conn,
    owner: owner
  } do
    {:ok, view, _} = live(conn, "/app/add")

    invalid =
      file_input(view, "#photo-form", :photo, [
        %{name: "notes.txt", content: "text", type: "text/plain"}
      ])

    preflight_upload(invalid)
    assert has_element?(view, ".upload-error[role='alert']", "JPG, PNG, or WebP")
    render_submit(view, "save-photo", %{})
    assert Food.list_food_photos!(actor: owner, page: [limit: 24]).results == []
    view |> element("button[phx-click='cancel-upload']") |> render_click()

    oversized =
      file_input(view, "#photo-form", :photo, [
        %{name: "large.png", content: :binary.copy(<<0>>, 8_000_001), type: "image/png"}
      ])

    preflight_upload(oversized)
    assert has_element?(view, ".upload-error[role='alert']", "smaller than 8 MB")
    render_submit(view, "save-photo", %{})
    assert Food.list_food_photos!(actor: owner, page: [limit: 24]).results == []
  end

  test "the LiveView requests 24 photos per page and appends both journal views", %{
    conn: conn,
    owner: owner
  } do
    file = upload()
    for _ <- 1..49, do: create_unanalyzed_photo(owner, file)

    expected_ids =
      Food.list_food_photos!(actor: owner, page: [limit: 49]).results |> Enum.map(& &1.id)

    {:ok, view, _} = live(conn, "/app")
    assert has_element?(view, "#photo-count", "49")

    for expected_count <- [24, 48, 49] do
      if expected_count > 24, do: view |> element("#load-more") |> render_click()
      document = view |> render() |> LazyHTML.from_fragment()

      for {selector, prefix} <- [
            {"#photos article", "photos-"},
            {"#food-log-rows tr[id^='food_log-']", "food_log-"}
          ] do
        ids = document |> LazyHTML.query(selector) |> LazyHTML.attribute("id")
        assert ids == Enum.map(Enum.take(expected_ids, expected_count), &(prefix <> &1))
      end
    end

    assert has_element?(view, "#photo-count", "49")
    refute has_element?(view, "#load-more")
  end
end
