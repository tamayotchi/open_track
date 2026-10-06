defmodule OpenTrackWeb.PublicImageUrlsLiveTest do
  use OpenTrackWeb.ConnCase

  import Phoenix.LiveViewTest
  import OpenTrack.Fixtures

  alias OpenTrack.{Accounts, Food}

  test "existing images use the same public URLs across profile and home without moving storage",
       %{
         conn: conn
       } do
    owner = user()
    viewer = user()
    Accounts.follow_user!(owner.id, actor: viewer)
    Accounts.update_user_avatar!(owner, upload(), actor: owner)
    owner = Accounts.get_user_by_id!(owner.id, actor: owner, load: [avatar: :blob])
    photo = Food.create_food_photo!(upload(), actor: owner, load: [image: :blob])

    # Upload with the original backend first, then change only the serving endpoint.
    for {resource, prefix} <- [{Accounts.User, "avatars/"}, {Food.FoodPhoto, "food/"}] do
      original = Application.fetch_env!(:open_track, resource)
      on_exit(fn -> Application.put_env(:open_track, resource, original) end)

      Application.put_env(
        :open_track,
        resource,
        Keyword.put(original, :storage,
          service:
            {AshStorage.Service.S3,
             bucket: "test-bucket",
             prefix: prefix,
             endpoint_url: "https://account.r2.cloudflarestorage.com",
             region: "auto",
             public_base_url: "https://images.example.com",
             presigned: false}
        )
      )
    end

    avatar_url = "https://images.example.com/avatars/#{owner.avatar.blob.key}"
    image_url = "https://images.example.com/food/#{photo.image.blob.key}"
    conn = log_in(conn, viewer)

    {:ok, profile, _} = live(conn, "/app/profile/#{owner.nickname}")
    assert has_element?(profile, "#profile-avatar[src='#{avatar_url}']")
    assert has_element?(profile, "#photos-#{photo.id} img[src='#{image_url}']")

    {:ok, home, _} = live(conn, "/app")
    assert has_element?(home, "#posts-#{photo.id} header img[src='#{avatar_url}']")
    assert has_element?(home, "#posts-#{photo.id} .food-image[src='#{image_url}']")

    {:ok, reloaded, _} = live(conn, "/app/profile/#{owner.nickname}")
    assert has_element?(reloaded, "#profile-avatar[src='#{avatar_url}']")
    assert has_element?(reloaded, "#photos-#{photo.id} img[src='#{image_url}']")

    # Existing blobs still download through their stored backend, not the CDN URL.
    assert AshStorage.Operations.download(owner.avatar.blob) == {:ok, image_bytes()}
    assert AshStorage.Operations.download(photo.image.blob) == {:ok, image_bytes()}
  end
end
