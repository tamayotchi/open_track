defmodule OpenTrack.Accounts.User.Settings do
  @moduledoc """
  Per-user settings for health/fitness targets.

  Each user has at most one `Settings` record. The `:user_id` identity
  enforces this uniqueness at the database level.
  """

  use Ash.Resource,
    otp_app: :open_track,
    domain: OpenTrack.Accounts,
    authorizers: [Ash.Policy.Authorizer]

  code_interface do
    define :get_settings, action: :read, get_by: [:id]
    define :get_settings_for_user, action: :read, get_by: [:user_id]
    define :create_settings, action: :create
    define :update_settings, action: :update
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      accept [:target_weight_kg, :target_body_fat_percent]
      change relate_actor(:user)
      primary? true
    end
  end

  policies do
    policy always() do
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
