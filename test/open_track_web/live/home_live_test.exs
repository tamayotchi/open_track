defmodule OpenTrackWeb.HomeLiveTest do
  use OpenTrackWeb.ConnCase

  import Phoenix.LiveViewTest
  import OpenTrack.Fixtures
  import OpenTrack.AnalysisFixtures

  alias OpenTrack.{Accounts, Food}
  alias OpenTrackWeb.Timezones

  setup do
    configure_ai()
    %{viewer: user(), followed_user: user()}
  end

  test "home requires a login and links to the journal and upload flow", %{
    conn: conn,
    viewer: viewer
  } do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, "/app")
    {:ok, view, _} = live(log_in(conn, viewer), "/app")
    assert has_element?(view, "#nav-home[aria-current='page']", "Home")
    assert has_element?(view, "#header-profile[href='/app/profile/#{viewer.nickname}']")

    assert has_element?(
             view,
             "#bottom-nav .bottom-nav-inner > a:nth-child(2)#nav-add-food[href='/app/add']"
           )

    assert has_element?(view, "#bottom-nav .bottom-nav-inner > a:nth-child(3)#nav-account")
    refute has_element?(view, "#bottom-nav .bottom-nav-inner > a:nth-child(4)")
    assert has_element?(view, "#feed-posts[phx-update='stream']")
    assert has_element?(view, "#empty-feed", "Follow people")
    assert post_ids(view) == []
    refute has_element?(view, "#load-more-feed")
  end

  test "posts show public user identities, photos, local timestamps and expandable AI details", %{
    conn: conn,
    viewer: viewer,
    followed_user: followed_user
  } do
    Accounts.follow_user!(followed_user.id, actor: viewer)
    Accounts.create_settings!(%{timezone: "America/Bogota"}, actor: viewer)
    Accounts.update_user_avatar!(followed_user.id, upload(), actor: followed_user)
    stub_prediction(prediction(%{"description" => "<script>untrusted()</script>"}))
    photo = create_analyzed_photo(followed_user)
    own = create_unanalyzed_photo(viewer)
    unrelated = create_unanalyzed_photo(user())

    {:ok, view, _} = live(log_in(conn, viewer), "/app")
    assert post_ids(view) == ["posts-#{photo.id}"]

    assert has_element?(
             view,
             "#posts-#{photo.id} header a[href='/app/profile/#{followed_user.nickname}']"
           )

    assert has_element?(view, "#posts-#{photo.id} header img[src]")
    assert has_element?(view, "#posts-#{photo.id} .food-image[src]")
    assert has_element?(view, "#posts-#{photo.id}-analysis:not([open])", "AI food details")
    assert has_element?(view, "#posts-#{photo.id}-analysis", "520 kcal")
    assert has_element?(view, "#posts-#{photo.id}-analysis", "32 g")
    assert has_element?(view, "#posts-#{photo.id}-analysis", "Chicken rice bowl")
    assert has_element?(view, "#posts-#{photo.id}-analysis", "<script>untrusted()</script>")
    refute has_element?(view, "#posts-#{photo.id} script")

    local_time =
      photo.inserted_at
      |> Timezones.local_datetime("America/Bogota")
      |> Calendar.strftime("%b %-d, %Y · %H:%M %Z")

    assert has_element?(view, "#posts-#{photo.id} time", local_time)
    refute has_element?(view, "#posts-#{own.id}")
    refute has_element?(view, "#posts-#{unrelated.id}")
    refute has_element?(view, "[phx-click='delete-photo']")
    refute has_element?(view, "#feed-posts", to_string(followed_user.email))
    refute has_element?(view, "#feed-posts", followed_user.hashed_password)
  end

  test "load more appends in upload order and refresh resets for new posts and unfollows", %{
    conn: conn,
    viewer: viewer,
    followed_user: followed_user
  } do
    second_followed_user = user()
    Accounts.follow_user!(followed_user.id, actor: viewer)
    Accounts.follow_user!(second_followed_user.id, actor: viewer)
    file = upload()

    photos =
      for index <- 1..13 do
        create_unanalyzed_photo(
          if(rem(index, 2) == 0, do: followed_user, else: second_followed_user),
          file
        )
      end

    expected_ids = photos |> Enum.reverse() |> Enum.map(&"posts-#{&1.id}")

    {:ok, view, _} = live(log_in(conn, viewer), "/app")
    assert post_ids(view) == Enum.take(expected_ids, 12)
    view |> element("#load-more-feed") |> render_click()
    assert post_ids(view) == expected_ids
    refute has_element?(view, "#load-more-feed")
    render_click(view, "load-more")
    assert post_ids(view) == expected_ids

    newest = create_unanalyzed_photo(followed_user, file)
    view |> element("#refresh-feed") |> render_click()
    assert post_ids(view) == Enum.take(["posts-#{newest.id}" | expected_ids], 12)
    assert has_element?(view, "#load-more-feed")

    for followed <- [followed_user, second_followed_user] do
      follow = Accounts.get_follow!(followed.id, actor: viewer)
      Accounts.unfollow_user!(follow.id, actor: viewer)
    end

    view |> element("#refresh-feed") |> render_click()
    assert post_ids(view) == []
    assert has_element?(view, "#empty-feed")
    refute has_element?(view, "#load-more-feed")
  end

  test "refresh displays completed analyses and removes deleted posts", %{
    conn: conn,
    viewer: viewer,
    followed_user: followed_user
  } do
    Accounts.follow_user!(followed_user.id, actor: viewer)
    photo = create_unanalyzed_photo(followed_user)
    {:ok, view, _} = live(log_in(conn, viewer), "/app")
    assert has_element?(view, "#posts-#{photo.id}", "Not analyzed")

    stub_prediction()
    drain_analysis()
    view |> element("#refresh-feed") |> render_click()
    assert has_element?(view, "#posts-#{photo.id}-analysis", "520 kcal")

    Food.delete_food_photo!(photo.id, actor: followed_user)
    view |> element("#refresh-feed") |> render_click()
    assert post_ids(view) == []
  end

  test "failed and non-food analyses remain honest and read-only", %{
    conn: conn,
    viewer: viewer,
    followed_user: followed_user
  } do
    Accounts.follow_user!(followed_user.id, actor: viewer)

    failed =
      create_unanalyzed_photo(followed_user) |> Ash.Seed.update!(%{analysis_status: :failed})

    nonfood =
      create_unanalyzed_photo(followed_user)
      |> Ash.Seed.update!(%{
        analysis_status: :completed,
        analysis: prediction(%{"food_detected" => false})
      })

    {:ok, view, _} = live(log_in(conn, viewer), "/app")
    assert has_element?(view, "#posts-#{failed.id}", "Analysis failed")
    assert has_element?(view, "#posts-#{nonfood.id}", "No food identified")
    refute has_element?(view, "#feed-posts details")
    refute has_element?(view, "[phx-click='delete-photo']")
  end

  defp post_ids(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#feed-posts article")
    |> LazyHTML.attribute("id")
  end
end
