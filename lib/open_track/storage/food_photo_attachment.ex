defmodule OpenTrack.Storage.FoodPhotoAttachment do
  @moduledoc """
  Links a FoodPhoto to a Blob using `food_photo_id` and `blob_id`.

  AshStorage adds those relationships and the `name` attribute, which is
  `"image"` for a food photo. SQLite stores the attachment metadata.
  Manage these internal records through FoodPhoto's attachment actions,
  not through a public attachment API.
  """

  use Ash.Resource,
    otp_app: :open_track,
    domain: OpenTrack.Storage,
    extensions: [AshStorage.AttachmentResource],
    data_layer: AshSqlite.DataLayer

  attachment do
    blob_resource OpenTrack.Storage.Blob
    belongs_to_resource :food_photo, OpenTrack.Food.FoodPhoto
  end

  sqlite do
    table "food_photo_attachments"
    repo OpenTrack.Repo

    references do
      # AshStorage prefetches before destroy, then purges metadata in after_action.
      reference :food_photo, on_delete: :nilify
    end
  end

  attributes do
    uuid_primary_key :id

    # Temporarily nullable during the parent's destroy transaction so the
    # extension can purge the attachment and blob in its after_action hook.
    attribute :food_photo_id, :uuid do
      allow_nil? true
      public? true
    end

    create_timestamp :inserted_at
  end

  identities do
    identity :unique_food_photo_attachment, [:food_photo_id, :name]
  end
end
