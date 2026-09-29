defmodule OpenTrack.Food.FoodPhoto do
  @moduledoc """
  A user's food photo, its attached image, and optional food analysis.

  The `image` relationship points to a Storage.FoodPhotoAttachment, whose `blob`
  contains the object key and file metadata. AshSqlite persists metadata;
  the configured AshStorage service persists the image bytes.
  """

  use Ash.Resource,
    otp_app: :open_track,
    domain: OpenTrack.Food,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStorage],
    data_layer: AshSqlite.DataLayer

  alias OpenTrack.Food.Analysis

  storage do
    blob_resource OpenTrack.Storage.Blob
    attachment_resource OpenTrack.Storage.FoodPhotoAttachment

    has_one_attached :image, dependent: :purge
  end

  sqlite do
    table "food_photos"
    repo OpenTrack.Repo

    custom_indexes do
      index [:user_id, :inserted_at]
    end
  end

  actions do
    defaults [:read, :destroy]

    read :journal do
      prepare build(sort: [inserted_at: :desc])
      pagination keyset?: true
    end

    create :create do
      notifiers [Analysis.Notifier]
      primary? true
      accept []
      argument :uploaded_file, :file, allow_nil?: false

      change relate_actor(:user)

      change {AshStorage.Changes.AttachFile, argument: :uploaded_file, attachment: :image}
    end

    update :update_analysis do
      accept [:analysis, :analysis_status]

      validate attribute_equals(:analysis_status, :completed), where: present(:analysis)
      validate attribute_does_not_equal(:analysis_status, :completed), where: absent(:analysis)
    end

    read :nutrition_chart_data do
      argument :from, :utc_datetime_usec, allow_nil?: false
      argument :until, :utc_datetime_usec, allow_nil?: false

      filter expr(
               analysis_status == :completed and inserted_at >= ^arg(:from) and
                 inserted_at < ^arg(:until)
             )

      prepare build(select: [:analysis, :inserted_at])
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
      sensitive? true
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
