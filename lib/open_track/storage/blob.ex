defmodule OpenTrack.Storage.Blob do
  @moduledoc """
  Metadata for a stored file, not the file's bytes.

  AshStorage adds `key`, `filename`, `content_type`, `byte_size`, `checksum`,
  and storage service details. SQLite persists metadata; the configured disk or
  S3-compatible service stores bytes. Shared by food photos and user avatars. Access this internal
  resource through the owning Food or Accounts domain's actions; it is not
  intended to be exposed directly as an API.
  """

  use Ash.Resource,
    otp_app: :open_track,
    domain: OpenTrack.Storage,
    extensions: [AshStorage.BlobResource],
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "blobs"
    repo OpenTrack.Repo
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :inserted_at, type: :utc_datetime_usec
  end

  identities do
    identity :unique_key, [:key]
  end
end
