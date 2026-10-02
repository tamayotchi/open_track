defmodule OpenTrack.FoodTest do
  use OpenTrack.DataCase

  import Ash.Test
  import OpenTrack.Fixtures

  import OpenTrack.AnalysisFixtures,
    only: [create_unanalyzed_photo: 1, create_unanalyzed_photo: 2]

  alias Ash.Resource.Info
  alias OpenTrack.Food
  alias OpenTrack.Food.FoodPhoto
  alias OpenTrack.Storage.{Blob, FoodPhotoAttachment}

  test "uploads persist ownership, analysis defaults, metadata, and bytes" do
    owner = user()
    photo = create_unanalyzed_photo(owner)
    loaded = Food.get_food_photo!(photo.id, actor: owner, load: [image: :blob])

    assert loaded.user_id == owner.id
    assert loaded.analysis_status == :not_analyzed
    assert is_nil(loaded.analysis)
    assert loaded.image.blob.filename == "food.png"
    assert loaded.image.blob.content_type == "image/png"
    assert loaded.image.blob.byte_size == byte_size(image_bytes())
    assert AshStorage.Operations.download(loaded.image.blob) == {:ok, image_bytes()}
  end

  test "deleting by ID enforces ownership and purges attachment metadata and bytes" do
    owner = user()
    photo = create_unanalyzed_photo(owner)
    loaded = Food.get_food_photo!(photo.id, actor: owner, load: [image: :blob])

    for actor <- [user(), nil] do
      assert_has_error(
        Food.delete_food_photo(photo.id, actor: actor),
        Ash.Error.Invalid,
        fn error ->
          match?(%Ash.Error.Query.NotFound{}, error)
        end
      )

      assert Food.get_food_photo!(photo.id, actor: owner).id == photo.id
      assert AshStorage.Operations.download(loaded.image.blob) == {:ok, image_bytes()}
    end

    assert :ok = Food.delete_food_photo(photo.id, actor: owner)

    assert_has_error(Food.get_food_photo(photo.id, actor: owner), Ash.Error.Invalid, fn error ->
      match?(%Ash.Error.Query.NotFound{}, error)
    end)

    # Internal storage resources have no application code interfaces.
    assert is_nil(Ash.get!(FoodPhotoAttachment, loaded.image.id, not_found_error?: false))
    assert is_nil(Ash.get!(Blob, loaded.image.blob.id, not_found_error?: false))
    assert {:error, :not_found} = AshStorage.Operations.download(loaded.image.blob)

    assert_has_error(
      Food.delete_food_photo(photo.id, actor: owner),
      Ash.Error.Invalid,
      fn error ->
        match?(%Ash.Error.Query.NotFound{}, error)
      end
    )
  end

  test "the public profile read replaces the retired journal action" do
    assert is_nil(Info.action(FoodPhoto, :journal))
    assert %{type: :read} = Info.action(FoodPhoto, :for_profile)
  end

  test "profile photos are newest first, user-scoped, and honor the requested limit" do
    owner = user()
    file = upload()

    photos =
      for day <- 1..3 do
        create_unanalyzed_photo(owner, file)
        |> Ash.Seed.update!(%{inserted_at: DateTime.add(~U[2026-01-01 12:00:00Z], day, :day)})
      end

    create_unanalyzed_photo(user(), file)
    expected_ids = photos |> Enum.reverse() |> Enum.map(& &1.id)
    first_page = Food.list_food_photos!(owner.id, page: [limit: 2, count: true])

    assert Enum.map(first_page.results, & &1.id) == Enum.take(expected_ids, 2)
    assert first_page.count == 3
    assert first_page.more?

    last_page =
      Food.list_food_photos!(owner.id,
        page: [limit: 2, after: List.last(first_page.results).__metadata__.keyset]
      )

    assert Enum.map(last_page.results, & &1.id) == Enum.drop(expected_ids, 2)
    assert is_nil(last_page.count)
    refute last_page.more?
  end

  test "profile pagination does not skip or repeat photos with identical timestamps" do
    owner = user()
    file = upload()

    # Seed read-only timestamps so the tie is deterministic.
    photos =
      for _ <- 1..2 do
        create_unanalyzed_photo(owner, file)
        |> Ash.Seed.update!(%{inserted_at: ~U[2026-01-01 12:00:00.000000Z]})
      end

    first_page = Food.list_food_photos!(owner.id, page: [limit: 1])
    assert [first] = first_page.results
    assert first_page.more?

    second_page =
      Food.list_food_photos!(owner.id, page: [limit: 1, after: first.__metadata__.keyset])

    assert [second] = second_page.results
    refute second_page.more?
    assert Enum.sort([first.id, second.id]) == Enum.sort(Enum.map(photos, & &1.id))
  end

  test "record reads stay owner-only while profile photo reads are public" do
    owner = user()
    photo = create_unanalyzed_photo(owner)

    for actor <- [user(), nil] do
      assert_has_error(
        Food.get_food_photo(photo.id, actor: actor, load: :image_url),
        Ash.Error.Invalid,
        &match?(%Ash.Error.Query.NotFound{}, &1)
      )

      assert [public_photo] =
               Food.list_food_photos!(owner.id, actor: actor, page: [limit: 24], load: :image_url).results

      assert public_photo.id == photo.id
      assert is_binary(public_photo.image_url)
    end
  end

  test "creation requires an actor and a valid file, and rejects supplied ownership" do
    owner = user()
    file = upload()

    assert_has_error(Food.create_food_photo(file), Ash.Error.Invalid, fn error ->
      match?(%Ash.Error.Changes.InvalidRelationship{relationship: :user}, error)
    end)

    assert_has_error(
      Food.create_food_photo(file, %{user_id: owner.id}, actor: owner),
      Ash.Error.Invalid,
      &match?(%Ash.Error.Invalid.NoSuchInput{input: :user_id}, &1)
    )

    for {file, error_type} <- [
          {nil, Ash.Error.Changes.Required},
          {123, Ash.Error.Changes.InvalidArgument}
        ] do
      assert_has_error(Food.create_food_photo(file, actor: owner), Ash.Error.Invalid, fn error ->
        error.__struct__ == error_type and error.field == :uploaded_file
      end)
    end

    assert Food.list_food_photos!(owner.id, page: [limit: 24]).results == []
  end

  test "missing files raise from storage and roll back the photo" do
    owner = user()
    file = upload()
    File.rm!(file.path)

    assert_raise Ash.Error.Unknown, ~r/enoent/, fn ->
      Food.create_food_photo(file, actor: owner)
    end

    assert Food.list_food_photos!(owner.id, page: [limit: 24]).results == []
    assert AshStorage.Service.Test.list_keys() == []
  end

  test "storage failure rolls back the photo and preserves an existing avatar" do
    owner = user()
    OpenTrack.Accounts.update_user_avatar!(owner, upload(), actor: owner)
    original = OpenTrack.Accounts.get_user_by_id!(owner.id, actor: owner, load: [avatar: :blob])
    keys = AshStorage.Service.Test.list_keys() |> Enum.sort()

    for resource <- [OpenTrack.Food.FoodPhoto, OpenTrack.Accounts.User] do
      previous = Application.fetch_env!(:open_track, resource)
      on_exit(fn -> Application.put_env(:open_track, resource, previous) end)

      Application.put_env(:open_track, resource,
        storage: [service: {OpenTrack.UnavailableStorage, []}]
      )
    end

    assert {:error, _} = Food.create_food_photo(upload(), actor: owner)
    assert Food.list_food_photos!(owner.id, page: [limit: 24]).results == []
    assert {:error, _} = OpenTrack.Accounts.update_user_avatar(owner, upload(), actor: owner)
    loaded = OpenTrack.Accounts.get_user_by_id!(owner.id, actor: owner, load: [avatar: :blob])
    assert loaded.avatar.id == original.avatar.id
    assert AshStorage.Operations.download(loaded.avatar.blob) == {:ok, image_bytes()}
    assert Enum.sort(AshStorage.Service.Test.list_keys()) == keys
  end
end
