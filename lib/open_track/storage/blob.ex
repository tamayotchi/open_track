defmodule OpenTrack.Storage.Blob do
  @moduledoc """
  Metadata for a stored file, not the file's bytes.

  AshStorage adds `key`, `filename`, `content_type`, `byte_size`, `checksum`,
  and storage service details. The bytes live in R2. No persistence data layer
  is configured yet. Shared by food photos and user avatars. Access this internal
  resource through the owning Food or Accounts domain's actions; it is not
  intended to be exposed directly as an API.
  """

  use Ash.Resource,
    otp_app: :open_track,
    domain: OpenTrack.Storage,
    extensions: [AshStorage.BlobResource]

  attributes do
    uuid_primary_key :id
    create_timestamp :inserted_at, type: :utc_datetime_usec
  end

  identities do
    identity :unique_key, [:key]
  end
end
