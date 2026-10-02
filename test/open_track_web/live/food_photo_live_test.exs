defmodule OpenTrackWeb.FoodPhotoLiveTest do
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

  test "the upload page does not query photo history or handle profile events", %{conn: conn} do
    ref = make_ref()
    handler = {__MODULE__, ref}

    :ok =
      :telemetry.attach(
        handler,
        [:open_track, :repo, :query],
        &__MODULE__.record_photo_query/4,
        {self(), ref}
      )

    try do
      {:ok, view, _} = live(conn, "/app/add")
      assert view.module == OpenTrackWeb.AddFoodLive
      assert has_element?(view, "#photo-form")
      refute has_element?(view, "#photos")
      refute has_element?(view, "#chart-range")

      for event <- ["range", "load-more", "set-view", "delete-photo"] do
        render_click(view, event, %{
          "days" => "90",
          "mode" => "table",
          "id" => Ash.UUID.generate()
        })
      end

      refute_receive {^ref, :photo_query}
      assert has_element?(view, "#photo-form")
    after
      :telemetry.detach(handler)
    end
  end

  test "owned profile and card/table switch", %{conn: conn, owner: owner} do
    {:ok, view, _} = live(conn, "/app/profile/#{owner.nickname}")
    assert has_element?(view, "#nav-account[aria-current='page']")
    assert has_element?(view, "#profile-settings-link[href='/app/account/settings']")
    assert has_element?(view, "a[href='/app/account/settings#targets']")
    assert has_element?(view, "a[href='/app/account/settings#timezone-preferences']")
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
    assert has_element?(view, "#nav-add-food[aria-current='page']")
    refute has_element?(view, "#nav-account[aria-current]")

    upload =
      file_input(view, "#photo-form", :photo, [
        %{name: "lunch.png", content: image_bytes(), type: "image/png"}
      ])

    render_upload(upload, "lunch.png")

    {:ok, profile, _} =
      view
      |> form("#photo-form")
      |> render_submit()
      |> follow_redirect(conn, "/app/profile/#{owner.nickname}")

    assert has_element?(profile, "#photo-count", "1")

    assert [photo] =
             Food.list_food_photos!(owner.id, page: [limit: 24], load: :image_url).results

    ExUnit.CaptureLog.capture_log(fn -> drain_analysis() end)
    assert_analysis(photo.id, owner, :failed)
    assert is_binary(photo.image_url)
    assert has_element?(profile, "#photos-#{photo.id} img[src='#{photo.image_url}']")
    {:ok, reloaded, _} = live(conn, "/app/profile/#{owner.nickname}")
    assert has_element?(reloaded, "#photos-#{photo.id} img[src='#{photo.image_url}']")
    assert has_element?(reloaded, "#food_log-#{photo.id} img[src='#{photo.image_url}']")
    reloaded |> element("#photos-#{photo.id} button[phx-click='delete-photo']") |> render_click()
    refute has_element?(reloaded, "#photos-#{photo.id}")
    refute has_element?(reloaded, "#food_log-#{photo.id}")
    assert has_element?(reloaded, "#photo-count", "0")
    assert has_element?(reloaded, "#empty-journal")
    assert Food.list_food_photos!(owner.id, page: [limit: 24]).results == []
  end

  test "another user's photos stay hidden and forged deletion events fail", %{
    conn: conn,
    owner: owner
  } do
    other = user()
    photo = create_unanalyzed_photo(other)
    {:ok, view, _} = live(conn, "/app/profile/#{owner.nickname}")
    refute has_element?(view, "#photos-#{photo.id}")
    refute has_element?(view, "#food_log-#{photo.id}")
    assert has_element?(view, "#photo-count", "0")

    render_click(view, "delete-photo", %{"id" => photo.id})
    assert has_element?(view, "#flash-error", "Could not delete this photo.")
    assert Food.get_food_photo!(photo.id, actor: other).id == photo.id
  end

  test "unknown and malformed photo IDs show a deletion error without crashing", %{
    conn: conn,
    owner: owner
  } do
    {:ok, view, _} = live(conn, "/app/profile/#{owner.nickname}")

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
    assert has_element?(view, "#photo-form")
    refute has_element?(view, "#photos")
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
    assert Food.list_food_photos!(owner.id, page: [limit: 24]).results == []
    view |> element("button[phx-click='cancel-upload']") |> render_click()

    oversized =
      file_input(view, "#photo-form", :photo, [
        %{name: "large.png", content: :binary.copy(<<0>>, 8_000_001), type: "image/png"}
      ])

    preflight_upload(oversized)
    assert has_element?(view, ".upload-error[role='alert']", "smaller than 8 MB")
    render_submit(view, "save-photo", %{})
    assert Food.list_food_photos!(owner.id, page: [limit: 24]).results == []
  end

  test "the LiveView requests 24 photos per page and appends both journal views", %{
    conn: conn,
    owner: owner
  } do
    file = upload()
    for _ <- 1..49, do: create_unanalyzed_photo(owner, file)

    expected_ids =
      Food.list_food_photos!(owner.id, page: [limit: 49]).results |> Enum.map(& &1.id)

    {:ok, view, _} = live(conn, "/app/profile/#{owner.nickname}")
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

  def record_photo_query(_event, _measurements, metadata, {pid, ref}) do
    if String.contains?(metadata.query, ~s("food_photos")) do
      send(pid, {ref, :photo_query})
    end
  end
end
