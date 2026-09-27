defmodule OpenTrack.Storage.UserAttachment do
  @moduledoc """
  Links a User to a shared Storage.Blob using `user_id` and `blob_id`.

  Avatar attachments use the name `"avatar"`. Keeping user attachments separate
  from food photo attachments lets each resource require its own owner.
  SQLite persists this metadata. Manage these internal records
  through the Accounts domain's avatar actions, not a public storage API.
  """

  use Ash.Resource,
    otp_app: :open_track,
    domain: OpenTrack.Storage,
    extensions: [AshStorage.AttachmentResource],
    data_layer: AshSqlite.DataLayer

  attachment do
    blob_resource OpenTrack.Storage.Blob
    belongs_to_resource :user, OpenTrack.Accounts.User
  end

  sqlite do
    table "user_attachments"
    repo OpenTrack.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
  end

  identities do
    identity :unique_user_attachment, [:user_id, :name]
  end
end
