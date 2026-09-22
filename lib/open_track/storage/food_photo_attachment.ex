defmodule OpenTrack.Storage.FoodPhotoAttachment do
  @moduledoc """
  Links a FoodPhoto to a Blob using `food_photo_id` and `blob_id`.

  AshStorage adds those relationships and the `name` attribute, which is
  `"image"` for a food photo. No persistence data layer is configured yet.
  Manage these internal records through FoodPhoto's attachment actions,
  not through a public attachment API.
  """

  use Ash.Resource,
    otp_app: :open_track,
    domain: OpenTrack.Storage,
    extensions: [AshStorage.AttachmentResource]

  attachment do
    blob_resource OpenTrack.Storage.Blob
    belongs_to_resource :food_photo, OpenTrack.Food.FoodPhoto
  end

  attributes do
    uuid_primary_key :id

    # The extension supports multiple parent types with nullable foreign keys.
    # This resource only supports FoodPhoto, so its parent must be present.
    attribute :food_photo_id, :uuid do
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
  end

  identities do
    identity :unique_food_photo_attachment, [:food_photo_id, :name]
  end
end
