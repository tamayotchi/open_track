defmodule OpenTrack.Accounts.User do
  @moduledoc "User accounts with password authentication and public nickname profiles."

  use Ash.Resource,
    otp_app: :open_track,
    domain: OpenTrack.Accounts,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication, AshStorage],
    data_layer: AshSqlite.DataLayer

  authentication do
    tokens do
      enabled? true
      token_resource OpenTrack.Accounts.Token
      signing_secret OpenTrack.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      password :password do
        identity_field :email
        register_action_accept [:nickname]
        hash_provider AshAuthentication.BcryptProvider
        sign_in_tokens_enabled? false
      end

      remember_me :remember_me
    end
  end

  field_policies do
    private_fields :include

    field_policy [:email, :hashed_password] do
      forbid_if action(:read_public_identity)
      authorize_if always()
    end

    field_policy :* do
      authorize_if always()
    end
  end

  storage do
    blob_resource OpenTrack.Storage.Blob
    attachment_resource OpenTrack.Storage.UserAttachment

    has_one_attached :avatar, dependent: :purge
  end

  sqlite do
    table "users"
    repo OpenTrack.Repo
  end

  actions do
    defaults [:read]

    read :read_public_identity do
      description "Public user identity for display alongside food photos."
      prepare build(select: [:id, :nickname])
    end

    read :public_profile do
      argument :nickname, :ci_string, allow_nil?: false
      get? true
      filter expr(nickname == ^arg(:nickname))
      prepare build(select: [:id, :nickname], load: [:public_settings])
    end

    read :get_by_subject do
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    update :update_avatar do
      accept []
      require_atomic? false
      argument :uploaded_avatar, :file, allow_nil?: false

      change {AshStorage.Changes.AttachFile, argument: :uploaded_avatar, attachment: :avatar}
    end

    update :change_password do
      # Use this action to allow users to change their password by providing
      # their current password and a new password.

      require_atomic? false
      accept []
      argument :current_password, :string, sensitive?: true, allow_nil?: false

      argument :password, :string,
        sensitive?: true,
        allow_nil?: false,
        constraints: [min_length: 8]

      argument :password_confirmation, :string, sensitive?: true, allow_nil?: false

      validate confirm(:password, :password_confirmation)

      validate {AshAuthentication.Strategy.Password.PasswordValidation,
                strategy_name: :password, password_argument: :current_password}

      change {AshAuthentication.Strategy.Password.HashPasswordChange, strategy_name: :password}
    end

    read :get_by_email do
      description "Looks up a user by their email"
      get_by :email
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action([:public_profile, :read_public_identity]) do
      authorize_if always()
    end

    policy action([
             :read,
             :change_password,
             :update_avatar,
             :attach_avatar,
             :detach_avatar,
             :purge_avatar
           ]) do
      authorize_if expr(id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false

      constraints max_length: 160,
                  match: ~r/^[^@\s,;]+@[^@\s,;]+\.[^@\s,;]+$/,
                  casing: :lower

      public? true
    end

    attribute :nickname, :ci_string do
      allow_nil? false
      public? true
      constraints casing: :lower
    end

    attribute :hashed_password, :string do
      allow_nil? false
      sensitive? true
    end
  end

  relationships do
    has_one :settings, OpenTrack.Accounts.User.Settings

    has_many :follower_connections, OpenTrack.Accounts.Follow do
      destination_attribute :followed_id
    end

    has_many :following_connections, OpenTrack.Accounts.Follow do
      destination_attribute :follower_id
    end
  end

  calculations do
    calculate :public_settings,
              :map,
              expr(%{
                target_weight_kg: settings.target_weight_kg,
                target_body_fat_percent: settings.target_body_fat_percent,
                timezone: settings.timezone
              })
  end

  aggregates do
    count :followers_count, :follower_connections do
      authorize? false
    end

    count :following_count, :following_connections do
      authorize? false
    end
  end

  identities do
    identity :unique_email, [:email]

    identity :unique_nickname, [:nickname] do
      message "has already been taken"
    end
  end
end
