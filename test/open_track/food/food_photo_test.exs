defmodule OpenTrack.Food.FoodPhotoTest do
  use ExUnit.Case, async: true

  alias OpenTrack.Accounts.User
  alias OpenTrack.Food.FoodPhoto
  alias OpenTrack.Storage.{Blob, FoodPhotoAttachment}

  test "is registered in the food domain" do
    assert FoodPhoto in Ash.Domain.Info.resources(OpenTrack.Food)
  end

  test "matches the food photo attributes and defaults" do
    assert Ash.Resource.Info.primary_key(FoodPhoto) == [:id]
    assert Ash.Resource.Info.attribute(FoodPhoto, :id).type == Ash.Type.UUID

    refute Ash.Resource.Info.attribute(FoodPhoto, :storage_key)
    refute Ash.Resource.Info.identity(FoodPhoto, :unique_storage_key)

    status = Ash.Resource.Info.attribute(FoodPhoto, :analysis_status)
    assert status.type == Ash.Type.Atom
    assert status.default == :not_analyzed
    assert status.constraints[:one_of] == [:not_analyzed, :completed, :failed]
    refute status.allow_nil?

    analysis = Ash.Resource.Info.attribute(FoodPhoto, :analysis)
    assert analysis.type == Ash.Type.Map
    assert analysis.allow_nil?

    inserted_at = Ash.Resource.Info.attribute(FoodPhoto, :inserted_at)
    assert inserted_at.type == Ash.Type.UtcDatetimeUsec
    refute inserted_at.allow_nil?
    refute inserted_at.writable?
    assert is_function(inserted_at.default, 0)

    updated_at = Ash.Resource.Info.attribute(FoodPhoto, :updated_at)
    assert updated_at.type == Ash.Type.UtcDatetimeUsec
    refute updated_at.allow_nil?
    refute updated_at.writable?
    assert is_function(updated_at.default, 0)
    assert is_function(updated_at.update_default, 0)
  end

  test "analysis status only allows the configured atoms" do
    status = Ash.Resource.Info.attribute(FoodPhoto, :analysis_status)

    for value <- [:not_analyzed, :completed, :failed] do
      assert {:ok, ^value} = Ash.Type.apply_constraints(status.type, value, status.constraints)
    end

    assert {:error, _} =
             Ash.Type.apply_constraints(status.type, :unknown_status, status.constraints)
  end

  test "requires a user with a UUID foreign key" do
    user = Ash.Resource.Info.relationship(FoodPhoto, :user)
    assert user.type == :belongs_to
    assert user.destination == OpenTrack.Accounts.User
    assert user.source_attribute == :user_id
    refute user.allow_nil?

    user_id = Ash.Resource.Info.attribute(FoodPhoto, :user_id)
    assert user_id.type == Ash.Type.UUID
    refute user_id.allow_nil?
  end

  test "declares one image linked through an attachment and a blob" do
    assert AshStorage.Info.storage_blob_resource!(FoodPhoto) == Blob
    assert AshStorage.Info.storage_attachment_resource!(FoodPhoto) == FoodPhotoAttachment
    assert {:ok, %{type: :one, dependent: :purge}} = AshStorage.Info.attachment(FoodPhoto, :image)

    image = Ash.Resource.Info.relationship(FoodPhoto, :image)
    assert image.type == :has_one
    assert image.destination == FoodPhotoAttachment
    assert image.destination_attribute == :food_photo_id
    assert Ash.Resource.Info.calculation(FoodPhoto, :image_url)

    for name <- [:attach_image, :detach_image, :purge_image] do
      assert Ash.Resource.Info.action(FoodPhoto, name).type == :update
    end
  end

  test "image inherits the resource service instead of defining its own" do
    {:ok, image} = AshStorage.Info.attachment(FoodPhoto, :image)

    assert is_nil(image.service)
  end

  test "tests override the resource service with in-memory storage, never R2" do
    {:ok, image} = AshStorage.Info.attachment(FoodPhoto, :image)

    assert AshStorage.Info.service_for_attachment(FoodPhoto, image) ==
             {:ok, {AshStorage.Service.Test, []}}
  end

  test "creating a photo requires an uploaded file and an actor" do
    actor = %User{id: Ash.UUID.generate()}
    file = Ash.Type.File.from_path("/tmp/lunch.jpg")

    changeset = Ash.Changeset.for_create(FoodPhoto, :create, %{uploaded_file: file}, actor: actor)
    assert changeset.valid?
    assert Ash.Changeset.get_attribute(changeset, :user_id) == actor.id
    assert Ash.Changeset.get_attribute(changeset, :analysis_status) == :not_analyzed
    assert Ash.can?(changeset, actor)

    missing_file = Ash.Changeset.for_create(FoodPhoto, :create, %{}, actor: actor)
    refute missing_file.valid?

    missing_actor = Ash.Changeset.for_create(FoodPhoto, :create, %{uploaded_file: file})
    refute missing_actor.valid?
    refute Ash.can?(missing_actor, nil)
  end

  test "ownership cannot be supplied by the caller" do
    changeset =
      Ash.Changeset.for_create(
        FoodPhoto,
        :create,
        %{uploaded_file: Ash.Type.File.from_path("/tmp/lunch.jpg"), user_id: Ash.UUID.generate()},
        actor: %User{id: Ash.UUID.generate()}
      )

    refute changeset.valid?
  end

  test "reads only return the actor's photos without needing a database" do
    actor = %User{id: Ash.UUID.generate()}
    own_photo = %FoodPhoto{id: Ash.UUID.generate(), user_id: actor.id}
    other_photo = %FoodPhoto{id: Ash.UUID.generate(), user_id: Ash.UUID.generate()}

    photos =
      FoodPhoto
      |> Ash.Query.for_read(:read, %{}, actor: actor)
      |> Ash.DataLayer.Simple.set_data([own_photo, other_photo])
      |> Ash.read!()

    assert Enum.map(photos, & &1.id) == [own_photo.id]
  end

  test "attachment operations are only authorized for the photo owner" do
    owner = %User{id: Ash.UUID.generate()}
    other_user = %User{id: Ash.UUID.generate()}
    photo = %FoodPhoto{id: Ash.UUID.generate(), user_id: owner.id}

    for {action, params} <- [
          attach_image: %{io: "image bytes", filename: "lunch.jpg"},
          detach_image: %{},
          purge_image: %{}
        ] do
      assert Ash.can?({photo, action, params}, owner, run_queries?: false)
      refute Ash.can?({photo, action, params}, other_user, run_queries?: false)
      refute Ash.can?({photo, action, params}, nil, run_queries?: false)
    end
  end
end
