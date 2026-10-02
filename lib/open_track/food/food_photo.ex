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
    extensions: [AshStorage, AshOban],
    data_layer: AshSqlite.DataLayer

  alias OpenTrack.Food.Analysis

  storage do
    blob_resource OpenTrack.Storage.Blob
    attachment_resource OpenTrack.Storage.FoodPhotoAttachment

    has_one_attached :image, dependent: :purge
  end

  oban do
    triggers do
      trigger :process_analysis do
        worker_module_name __MODULE__.AshOban.Worker.ProcessAnalysis
        action :process_analysis
        queue :food_analysis
        scheduler_cron false
        read_action :read
        worker_read_action :read
        default_actor %{role: :food_analysis}
        lock_for_update? false
        max_attempts 3
        # Match the photo, not the nullable tenant argument (SQLite JSON nulls
        # don't compare equal). At most one unfinished analysis job per photo.
        worker_opts unique: [period: :infinity, states: :incomplete, keys: [:primary_key]]
        on_error :fail_analysis
        on_error_fails_job? true
      end
    end
  end

  sqlite do
    table "food_photos"
    repo OpenTrack.Repo

    custom_indexes do
      index [:user_id, :inserted_at]
    end
  end

  actions do
    defaults [:destroy]

    # Owner/internal reads also support AshOban's keyset-based trigger reads.
    read :read do
      primary? true
      pagination keyset?: true, required?: false
    end

    read :for_profile do
      description "Newest food photos belonging to a public profile."
      argument :user_id, :uuid, allow_nil?: false
      filter expr(user_id == ^arg(:user_id))
      prepare build(sort: [inserted_at: :desc])
      pagination keyset?: true
    end

    read :from_followed_users do
      description "Newest food photos uploaded by users the actor follows."
      filter expr(follow_from_viewer.follower_id == ^actor(:id))
      prepare build(sort: [inserted_at: :desc, id: :desc])
      pagination keyset?: true
    end

    read :nutrition_chart_data do
      argument :user_id, :uuid, allow_nil?: false
      argument :from, :utc_datetime_usec, allow_nil?: false
      argument :until, :utc_datetime_usec, allow_nil?: false

      filter expr(
               user_id == ^arg(:user_id) and analysis_status == :completed and
                 inserted_at >= ^arg(:from) and inserted_at < ^arg(:until)
             )

      prepare build(select: [:analysis, :inserted_at])
    end

    create :create do
      primary? true
      accept []
      argument :uploaded_file, :file, allow_nil?: false

      change relate_actor(:user)

      change run_oban_trigger(:process_analysis)
      change {AshStorage.Changes.AttachFile, argument: :uploaded_file, attachment: :image}
    end

    update :process_analysis do
      accept []
      # The provider call must never hold a SQLite write transaction open.
      transaction? false
      require_atomic? false
      change Analysis.Process
    end

    update :fail_analysis do
      accept []
      change set_attribute(:analysis, nil)
      change set_attribute(:analysis_status, :failed)
    end
  end

  policies do
    # Internal analysis may read photos and save outcomes, not create or delete them.
    bypass [
      actor_attribute_equals(:role, :food_analysis),
      action([:read, :process_analysis, :fail_analysis])
    ] do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if relating_to_actor(:user)
    end

    policy action(:from_followed_users) do
      authorize_if actor_present()
    end

    policy action([:for_profile, :nutrition_chart_data]) do
      authorize_if always()
    end

    policy action([
             :read,
             :destroy,
             :process_analysis,
             :fail_analysis,
             :attach_image,
             :detach_image,
             :purge_image
           ]) do
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
    has_one :follow_from_viewer, OpenTrack.Accounts.Follow do
      source_attribute :user_id
      destination_attribute :followed_id
      filter expr(follower_id == ^actor(:id))
    end

    belongs_to :user, OpenTrack.Accounts.User do
      allow_nil? false
      public? true
      read_action :read_public_identity
    end
  end
end
