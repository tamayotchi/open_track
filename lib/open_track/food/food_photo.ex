defmodule OpenTrack.Food.FoodPhoto do
  @moduledoc """
  A user's food photo, its attached image, and optional food analysis.

  The `image` relationship points to a Storage.FoodPhotoAttachment, whose `blob`
  contains the object key and file metadata. R2 stores the image bytes.

  No persistence data layer is configured yet. When adding one, configure the
  `food_photos` table, a restrictive user foreign key, and an index on
  `[:user_id, :inserted_at, :id]`, plus persistence for Blob and FoodPhotoAttachment.
  """

  use Ash.Resource,
    otp_app: :open_track,
    domain: OpenTrack.Food,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStorage]

  storage do
    # These connection settings are read when this resource is compiled.
    # Leave the service unset when R2 is not configured locally.
    if System.get_env("R2_ACCOUNT_ID") do
      service {AshStorage.Service.S3,
               bucket: "open-track",
               prefix: "food/",
               endpoint_url:
                 "https://#{System.fetch_env!("R2_ACCOUNT_ID")}.r2.cloudflarestorage.com",
               region: "auto",
               access_key_id_env: "R2_ACCESS_KEY_ID",
               secret_access_key_env: "R2_SECRET_ACCESS_KEY",
               presigned: true,
               expires_in: 300}
    end

    blob_resource OpenTrack.Storage.Blob
    attachment_resource OpenTrack.Storage.FoodPhotoAttachment

    has_one_attached :image, dependent: :purge
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept []
      argument :uploaded_file, :file, allow_nil?: false

      change relate_actor(:user)
      change {AshStorage.Changes.AttachFile, argument: :uploaded_file, attachment: :image}
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if relating_to_actor(:user)
    end

    policy action_type([:read, :update, :destroy]) do
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :analysis_status, :atom do
      constraints one_of: [:not_analyzed, :completed, :failed]
      allow_nil? false
      default :not_analyzed
      public? true
    end

    attribute :analysis, :map do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, OpenTrack.Accounts.User do
      allow_nil? false
      public? true
    end
  end
end
