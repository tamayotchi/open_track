defmodule OpenTrack.Accounts.User.Settings do
  @moduledoc """
  Per-user settings for health/fitness targets and local calendar preferences.

  Each user has at most one `Settings` record. The `:user_id` identity
  enforces this uniqueness at the database level.
  """

  use Ash.Resource,
    otp_app: :open_track,
    domain: OpenTrack.Accounts,
    authorizers: [Ash.Policy.Authorizer],
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "settings"
    repo OpenTrack.Repo
    migration_defaults timezone: "\"Etc/UTC\""
  end

  actions do
    defaults [:read, :destroy]

    update :update do
      primary? true
      accept [:target_weight_kg, :target_body_fat_percent, :timezone]
    end

    create :create do
      accept [:target_weight_kg, :target_body_fat_percent, :timezone]
      change relate_actor(:user)
      primary? true
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

    attribute :target_weight_kg, :float do
      constraints greater_than: 0, max: 200
      public? true
    end

    attribute :target_body_fat_percent, :float do
      constraints greater_than: 0, less_than: 100
      public? true
    end

    attribute :timezone, :string do
      allow_nil? false
      default "Etc/UTC"
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

  identities do
    identity :unique_user, [:user_id]
  end
end
