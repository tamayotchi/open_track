defmodule OpenTrack.FoodTest do
  use ExUnit.Case, async: true

  import Ash.Test

  alias OpenTrack.Accounts.User
  alias OpenTrack.Food
  alias OpenTrack.Food.FoodPhoto

  setup do
    owner = %User{id: Ash.UUID.generate()}
    other_user = %User{id: Ash.UUID.generate()}
    photo = %FoodPhoto{id: Ash.UUID.generate(), user_id: owner.id}
    another_photo = %FoodPhoto{id: Ash.UUID.generate(), user_id: owner.id}
    other_users_photo = %FoodPhoto{id: Ash.UUID.generate(), user_id: other_user.id}

    # No persistence data layer is configured; supply records for read tests.
    query = Ash.DataLayer.Simple.set_data(FoodPhoto, [another_photo, other_users_photo, photo])

    %{owner: owner, other_user: other_user, photo: photo, query: query}
  end

  describe "create_food_photo" do
    test "requires the uploaded_file argument", %{owner: owner} do
      result = Food.create_food_photo(nil, actor: owner)

      assert_has_error(result, Ash.Error.Invalid, fn error ->
        match?(%Ash.Error.Changes.Required{field: :uploaded_file}, error)
      end)
    end

    test "rejects an invalid file input", %{owner: owner} do
      result = Food.create_food_photo(123, actor: owner)

      assert_has_error(result, Ash.Error.Invalid, fn error ->
        match?(%Ash.Error.Changes.InvalidArgument{field: :uploaded_file}, error)
      end)
    end

    test "requires an actor" do
      file = Ash.Type.File.from_path("/tmp/lunch.jpg")
      result = Food.create_food_photo(file)

      assert_has_error(result, Ash.Error.Invalid, fn error ->
        match?(%Ash.Error.Changes.InvalidRelationship{relationship: :user}, error)
      end)
    end

    test "does not accept caller-supplied ownership", %{owner: owner, other_user: other_user} do
      file = Ash.Type.File.from_path("/tmp/lunch.jpg")
      result = Food.create_food_photo(file, %{user_id: other_user.id}, actor: owner)

      assert_has_error(result, Ash.Error.Invalid, fn error ->
        match?(%Ash.Error.Invalid.NoSuchInput{input: :user_id}, error)
      end)
    end
  end

  describe "get_food_photo" do
    test "finds the owner's photo by ID", %{owner: owner, photo: photo, query: query} do
      result = Food.get_food_photo!(photo.id, actor: owner, query: query)

      assert result.id == photo.id
      assert result.user_id == owner.id
    end

    test "returns not found for an unknown ID", %{owner: owner, query: query} do
      result = Food.get_food_photo(Ash.UUID.generate(), actor: owner, query: query)

      assert_has_error(result, Ash.Error.Invalid, fn error ->
        match?(%Ash.Error.Query.NotFound{}, error)
      end)
    end

    test "does not expose another user's photo", %{
      other_user: other_user,
      photo: photo,
      query: query
    } do
      result = Food.get_food_photo(photo.id, actor: other_user, query: query)

      assert_has_error(result, Ash.Error.Invalid, fn error ->
        match?(%Ash.Error.Query.NotFound{}, error)
      end)
    end

    test "does not expose photos without an actor", %{photo: photo, query: query} do
      result = Food.get_food_photo(photo.id, query: query)

      assert_has_error(result, Ash.Error.Invalid, fn error ->
        match?(%Ash.Error.Query.NotFound{}, error)
      end)
    end
  end
end
