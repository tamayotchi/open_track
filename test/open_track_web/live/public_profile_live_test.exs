defmodule OpenTrackWeb.PublicProfileLiveTest do
  use OpenTrackWeb.ConnCase

  import Phoenix.LiveViewTest
  import OpenTrack.Fixtures
  import OpenTrack.AnalysisFixtures

  alias OpenTrack.{Accounts, Food}

  setup do
    configure_ai()
    %{owner: user(%{nickname: "juantamayo26"})}
  end

  test "visitors can follow and unfollow without seeing connection details", %{
    conn: conn,
    owner: owner
  } do
    visitor = user()
    other_follower = user()
    Accounts.follow_user!(owner.id, actor: other_follower)
    Accounts.follow_user!(other_follower.id, actor: owner)

    {:ok, view, _} = live(log_in(conn, visitor), "/app/profile/juantamayo26")
    assert has_element?(view, "#profile-followers dd", "1")
    assert has_element?(view, "#profile-following dd", "1")
    assert has_element?(view, "#profile-follow-button[phx-click='follow']", "Follow")
    refute has_element?(view, "#public-profile", to_string(other_follower.nickname))
    refute has_element?(view, "#profile-followers a")
    refute has_element?(view, "#profile-following a")

    # Client-supplied IDs cannot change the acting user or the target profile.
    render_click(view, "follow", %{"followed_id" => visitor.id, "follower_id" => owner.id})
    assert has_element?(view, "#profile-followers dd", "2")
    assert has_element?(view, "#profile-follow-button[phx-click='unfollow']", "Unfollow")
    render_click(view, "follow")
    assert has_element?(view, "#profile-followers dd", "2")

    {:ok, reloaded, _} = live(log_in(conn, visitor), "/app/profile/juantamayo26")
    assert has_element?(reloaded, "#profile-follow-button[phx-click='unfollow']")
    view |> element("#profile-follow-button") |> render_click()
    assert has_element?(view, "#profile-followers dd", "1")
    assert has_element?(view, "#profile-follow-button[phx-click='follow']")
    render_click(view, "unfollow")
    assert has_element?(view, "#profile-followers dd", "1")

    {:ok, account, _} = live(log_in(conn, owner), "/app/account")
    assert has_element?(account, "#account-followers", "1 Followers")
    assert has_element?(account, "#account-following", "1 Following")
  end

  test "anonymous visitors and owners cannot follow themselves or forge follow events", %{
    conn: conn,
    owner: owner
  } do
    for connection <- [conn, log_in(conn, owner)] do
      {:ok, view, _} = live(connection, "/app/profile/juantamayo26")
      refute has_element?(view, "#profile-follow-button")
      render_click(view, "follow")
      render_click(view, "unfollow")
      assert has_element?(view, "#profile-followers dd", "0")
      assert has_element?(view, "#profile-following dd", "0")
    end

    {:ok, anonymous, _} = live(conn, "/app/profile/juantamayo26")
    assert has_element?(anonymous, "#profile-follow-login[href='/users/log-in']")
    {:ok, missing, _} = live(log_in(conn, owner), "/app/profile/no-such-member")
    render_click(missing, "follow")
    render_click(missing, "unfollow")
    assert has_element?(missing, "#profile-not-found")
  end

  test "profile navigation resets counts and the visitor's follow state", %{
    conn: conn,
    owner: owner
  } do
    visitor = user()
    other = user(%{nickname: "another-journal"})
    Accounts.follow_user!(owner.id, actor: visitor)

    {:ok, view, _} = live(log_in(conn, visitor), "/app/profile/juantamayo26")
    assert has_element?(view, "#profile-follow-button[phx-click='unfollow']")
    render_patch(view, "/app/profile/another-journal")
    assert has_element?(view, "#profile-followers dd", "0")
    assert has_element?(view, "#profile-follow-button[phx-click='follow']")
    view |> element("#profile-follow-button") |> render_click()
    assert Accounts.get_follow!(other.id, actor: visitor)
    assert Accounts.get_follow!(owner.id, actor: visitor)
  end

  test "anonymous visitors see the owner's journal, estimates, targets and timezone", %{
    conn: conn,
    owner: owner
  } do
    Accounts.create_settings!(
      %{target_weight_kg: 72, target_body_fat_percent: 18, timezone: "America/Bogota"},
      actor: owner
    )

    Accounts.update_user_avatar!(owner, upload(), actor: owner)
    stub_prediction()
    photo = create_analyzed_photo(owner)
    other_photo = create_unanalyzed_photo(user())

    {:ok, view, _} = live(conn, "/app/profile/JuanTamayo26")
    assert has_element?(view, "#public-profile", "juantamayo26")
    assert has_element?(view, "#profile-avatar[src]")
    assert has_element?(view, "#header-login")
    assert has_element?(view, "#photo-count", "1")
    assert has_element?(view, "#photos-#{photo.id} img[src]")
    assert has_element?(view, "#photos-#{photo.id}-analysis", "Chicken rice bowl")
    assert has_element?(view, "#photos-#{photo.id}-analysis", "520 kcal")
    assert has_element?(view, "#targets-summary", "72")
    assert has_element?(view, "#targets-summary", "18")
    assert has_element?(view, "#journal-timezone", "America/Bogota")
    assert has_element?(view, "#calories-chart-values td", "520")
    assert has_element?(view, "#protein-chart-values td", "32.0")
    refute has_element?(view, "#photos-#{other_photo.id}")
    refute has_element?(view, "[phx-click='delete-photo']")
    refute has_element?(view, "#edit-targets")
    refute has_element?(view, "#photo-form")
    refute has_element?(view, "#bottom-nav")
    refute has_element?(view, "#main-content", to_string(owner.email))
    refute has_element?(view, "#main-content", owner.hashed_password)

    view |> element("#view-table") |> render_click()
    assert has_element?(view, "#food-log-panel:not([hidden])")
    assert has_element?(view, "#food_log-#{photo.id} img[src]")
    view |> element("#view-cards") |> render_click()
    assert has_element?(view, "#photos:not([hidden])")

    for days <- ["30", "90", "7"] do
      view |> form("#chart-range", days: days) |> render_change()
      assert has_element?(view, "#calories-chart .sample-week", "Last #{days} days")
      assert has_element?(view, "#calories-chart-values td", "520")
    end
  end

  test "logged-in visitors still see the requested owner, and no visitor can mutate it", %{
    conn: conn,
    owner: owner
  } do
    photo = create_unanalyzed_photo(owner)
    visitor = user()
    visitor_photo = create_unanalyzed_photo(visitor)

    for connection <- [conn, log_in(conn, visitor), log_in(conn, owner)] do
      {:ok, view, _} = live(connection, "/app/profile/juantamayo26")
      assert has_element?(view, "#photos-#{photo.id}")
      refute has_element?(view, "#photos-#{visitor_photo.id}")
      refute has_element?(view, "[phx-click='delete-photo']")

      render_click(view, "delete-photo", %{"id" => photo.id})
      render_submit(view, "save-photo", %{})
      render_submit(view, "save-targets", %{"targets" => %{"target_weight_kg" => "80"}})
      assert Food.get_food_photo!(photo.id, actor: owner).id == photo.id

      assert Accounts.get_user_by_id!(owner.id, actor: owner, load: :settings).settings == nil

      assert has_element?(view, "#photos-#{photo.id}")
    end
  end

  test "public pagination appends both views without including other users", %{
    conn: conn,
    owner: owner
  } do
    file = upload()
    for _ <- 1..25, do: create_unanalyzed_photo(owner, file)
    other_photo = create_unanalyzed_photo(user(), file)

    ids =
      Food.list_food_photos!(owner.id, page: [limit: 25]).results |> Enum.map(& &1.id)

    {:ok, view, _} = live(conn, "/app/profile/juantamayo26")
    assert has_element?(view, "#photo-count", "25")

    for count <- [24, 25] do
      if count == 25, do: view |> element("#load-more") |> render_click()
      document = view |> render() |> LazyHTML.from_fragment()

      for {selector, prefix} <- [
            {"#photos article", "photos-"},
            {"#food-log-rows tr[id^='food_log-']", "food_log-"}
          ] do
        assert document |> LazyHTML.query(selector) |> LazyHTML.attribute("id") ==
                 Enum.map(Enum.take(ids, count), &(prefix <> &1))
      end
    end

    refute has_element?(view, "#load-more")
    refute has_element?(view, "#photos-#{other_photo.id}")
  end

  test "empty profiles default to UTC without prompting the visitor to upload", %{conn: conn} do
    {:ok, view, _} = live(conn, "/app/profile/juantamayo26")
    assert has_element?(view, "#empty-journal", "No food moments yet")
    assert has_element?(view, "#photo-count", "0")
    assert has_element?(view, "#journal-timezone", "UTC")
    assert has_element?(view, "#targets-summary", "Not set")
    refute has_element?(view, "#empty-journal a")
    refute has_element?(view, "#profile-avatar")
  end

  test "navigation between profiles resets the journal, settings and chart range", %{
    conn: conn,
    owner: owner
  } do
    photo = create_unanalyzed_photo(owner)
    Accounts.create_settings!(%{target_weight_kg: 72, timezone: "America/Bogota"}, actor: owner)
    user(%{nickname: "another-journal"})

    {:ok, view, _} = live(conn, "/app/profile/juantamayo26")
    view |> form("#chart-range", days: "90") |> render_change()
    render_patch(view, "/app/profile/another-journal")

    assert has_element?(view, "#public-profile", "another-journal")
    assert has_element?(view, "#photo-count", "0")
    assert has_element?(view, "#targets-summary", "Not set")
    assert has_element?(view, "#journal-timezone", "UTC")
    assert has_element?(view, "#calories-chart .sample-week", "Last 7 days")
    refute has_element?(view, "#photos-#{photo.id}")
    refute has_element?(view, "#food_log-#{photo.id}")
  end

  test "nicknames overlapping app routes use the same public profile URL", %{conn: conn} do
    for nickname <- ["add", "account"] do
      user(%{nickname: nickname})
      {:ok, public_view, _} = live(conn, "/app/profile/#{nickname}")
      assert has_element?(public_view, "#public-profile h1", nickname)
    end
  end

  test "unknown nicknames show a friendly page for anonymous and signed-in visitors", %{
    conn: conn,
    owner: owner
  } do
    for connection <- [conn, log_in(conn, owner)] do
      {:ok, view, _} = live(connection, "/app/profile/no-such-member")
      assert has_element?(view, "#profile-not-found h1", "Profile not found")
      assert has_element?(view, "#profile-not-found-home[href='/']", "Back to home")
      refute has_element?(view, "#public-profile")
      refute has_element?(view, "#photos")
      refute has_element?(view, "#targets-summary")
      refute has_element?(view, "#chart-range")

      # Stale or forged journal events must not load data for a missing profile.
      render_click(view, "load-more")
      render_change(view, "range", %{"days" => "30"})
      render_click(view, "set-view", %{"mode" => "table"})
      assert has_element?(view, "#profile-not-found")
    end
  end

  test "navigating to a missing profile clears the previous journal and can recover", %{
    conn: conn,
    owner: owner
  } do
    photo = create_unanalyzed_photo(owner)
    Accounts.create_settings!(%{target_weight_kg: 72}, actor: owner)
    {:ok, view, _} = live(conn, "/app/profile/juantamayo26")
    assert has_element?(view, "#photos-#{photo.id}")

    render_patch(view, "/app/profile/no-such-member")
    assert has_element?(view, "#profile-not-found")
    refute has_element?(view, "#photos-#{photo.id}")
    refute has_element?(view, "#food_log-#{photo.id}")
    refute has_element?(view, "#targets-summary")

    render_patch(view, "/app/profile/juantamayo26")
    refute has_element?(view, "#profile-not-found")
    assert has_element?(view, "#photos-#{photo.id}")
    assert has_element?(view, "#food_log-#{photo.id}")
    assert has_element?(view, "#targets-summary", "72")
  end

  test "the former short profile route is no longer available", %{conn: conn} do
    conn = get(conn, "/app/juantamayo26")
    assert conn.status == 404
  end

  test "existing app routes remain authenticated and account omits the profile sharing block", %{
    conn: conn,
    owner: owner
  } do
    for path <- ["/app", "/app/journal", "/app/add", "/app/account", "/app/account/settings"] do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, path)
    end

    {:ok, view, _} = live(log_in(conn, owner), "/app/account")
    assert has_element?(view, "#account-email", to_string(owner.email))
    refute has_element?(view, "#public-profile-link")

    refute has_element?(
             view,
             ".account-page",
             "Anyone with this link can see your photos, AI food details, charts, and targets."
           )
  end
end
