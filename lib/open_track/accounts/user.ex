defmodule OpenTrack.Accounts.User do
  @moduledoc "User accounts with password authentication and private avatars."

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
        hash_provider AshAuthentication.BcryptProvider
        sign_in_tokens_enabled? false
      end

      remember_me :remember_me
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

    read :sign_in_with_password do
      description "Attempt to sign in using a email and password."
      get? true

      argument :email, :ci_string do
        description "The email to use for retrieving the user."
        allow_nil? false
      end

      argument :password, :string do
        description "The password to check for the matching user."
        allow_nil? false
        sensitive? true
      end

      # validates the provided email and password and generates a token
      prepare AshAuthentication.Strategy.Password.SignInPreparation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    create :register_with_password do
      description "Register a new user with a email and password."

      argument :email, :ci_string do
        allow_nil? false
      end

      argument :password, :string do
        description "The proposed password for the user, in plain text."
        allow_nil? false
        constraints min_length: 8
        sensitive? true
      end

      argument :password_confirmation, :string do
        description "The proposed password for the user (again), in plain text."
        allow_nil? false
        sensitive? true
      end

      # Sets the email from the argument
      change set_attribute(:email, arg(:email))

      # Hashes the provided password
      change AshAuthentication.Strategy.Password.HashPasswordChange

      # Generates an authentication token for the user
      change AshAuthentication.GenerateTokenChange

      # validates that the password matches the confirmation
      validate AshAuthentication.Strategy.Password.PasswordConfirmationValidation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
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

    attribute :hashed_password, :string do
      allow_nil? false
      sensitive? true
    end
  end

  relationships do
    has_one :settings, OpenTrack.Accounts.User.Settings
  end

  identities do
    identity :unique_email, [:email]
  end
end
