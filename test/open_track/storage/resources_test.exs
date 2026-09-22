defmodule OpenTrack.Storage.ResourcesTest do
  use ExUnit.Case, async: true

  alias OpenTrack.Accounts.User
  alias OpenTrack.Food.FoodPhoto
  alias OpenTrack.Storage.{Blob, FoodPhotoAttachment, UserAttachment}

  test "registers shared blobs and separate attachments without a persistence data layer" do
    resources = Ash.Domain.Info.resources(OpenTrack.Storage)
    assert Blob in resources
    assert FoodPhotoAttachment in resources
    assert UserAttachment in resources

    for resource <- [User, FoodPhoto, Blob, FoodPhotoAttachment, UserAttachment] do
      assert Ash.DataLayer.data_layer(resource) == Ash.DataLayer.Simple
    end
  end

  test "AshStorage supplies blob metadata and the key identity lives on Blob" do
    assert Ash.Resource.Info.attribute(Blob, :key).type == Ash.Type.String
    refute Ash.Resource.Info.attribute(Blob, :key).allow_nil?
    assert Ash.Resource.Info.identity(Blob, :unique_key).keys == [:key]

    for name <- [:filename, :content_type, :byte_size, :checksum, :service_name, :service_opts] do
      assert Ash.Resource.Info.attribute(Blob, name)
    end

    assert Ash.Resource.Info.action(Blob, :create)
    assert Ash.Resource.Info.action(Blob, :purge_blob)
  end

  test "attachments link a named slot on a food photo to a blob" do
    photo = Ash.Resource.Info.relationship(FoodPhotoAttachment, :food_photo)
    assert photo.type == :belongs_to
    assert photo.destination == FoodPhoto
    assert photo.source_attribute == :food_photo_id
    refute Ash.Resource.Info.attribute(FoodPhotoAttachment, :food_photo_id).allow_nil?

    blob = Ash.Resource.Info.relationship(FoodPhotoAttachment, :blob)
    assert blob.type == :belongs_to
    assert blob.destination == Blob
    assert blob.source_attribute == :blob_id
    refute blob.allow_nil?

    assert Ash.Resource.Info.attribute(FoodPhotoAttachment, :name).type == Ash.Type.String
    refute Ash.Resource.Info.attribute(FoodPhotoAttachment, :record_type)
    refute Ash.Resource.Info.attribute(FoodPhotoAttachment, :record_id)

    assert Ash.Resource.Info.identity(FoodPhotoAttachment, :unique_food_photo_attachment).keys ==
             [:food_photo_id, :name]
  end

  test "user attachments require a user and share the blob resource" do
    user = Ash.Resource.Info.relationship(UserAttachment, :user)
    assert user.type == :belongs_to
    assert user.destination == User
    assert user.source_attribute == :user_id
    refute Ash.Resource.Info.attribute(UserAttachment, :user_id).allow_nil?
    refute Ash.Resource.Info.attribute(UserAttachment, :food_photo_id)

    blob = Ash.Resource.Info.relationship(UserAttachment, :blob)
    assert blob.destination == Blob
    assert blob.source_attribute == :blob_id
    refute blob.allow_nil?

    assert Ash.Resource.Info.attribute(UserAttachment, :name).type == Ash.Type.String
    refute Ash.Resource.Info.attribute(UserAttachment, :record_type)
    refute Ash.Resource.Info.attribute(UserAttachment, :record_id)

    assert Ash.Resource.Info.identity(UserAttachment, :unique_user_attachment).keys ==
             [:user_id, :name]
  end

  test "S3 support is compiled and credentials are not stored on blob records" do
    assert Code.ensure_loaded?(AshStorage.Service.S3)
    fields = AshStorage.Service.S3.service_opts_fields()

    assert Keyword.has_key?(fields, :endpoint_url)
    assert Keyword.has_key?(fields, :access_key_id_env)
    assert Keyword.has_key?(fields, :secret_access_key_env)
    refute Keyword.has_key?(fields, :access_key_id)
    refute Keyword.has_key?(fields, :secret_access_key)
  end
end
