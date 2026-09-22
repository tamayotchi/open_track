defmodule OpenTrack.Accounts.User do
  use Ash.Resource,
    otp_app: :open_track,
    domain: OpenTrack.Accounts,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication, AshStorage]

  authentication do
    add_ons do
      log_out_everywhere do
        apply_on_password_change? true
      end
    end

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
      end

      remember_me :remember_me
    end
  end

  storage do
    # Like FoodPhoto, configure R2 at compile time and resolve credentials at runtime.
    if System.get_env("R2_ACCOUNT_ID") do
      service {AshStorage.Service.S3,
               bucket: "open-track",
               prefix: "avatars/",
               endpoint_url:
                 "https://#{System.fetch_env!("R2_ACCOUNT_ID")}.r2.cloudflarestorage.com",
               region: "auto",
               access_key_id_env: "R2_ACCESS_KEY_ID",
               secret_access_key_env: "R2_SECRET_ACCESS_KEY",
               presigned: true,
               expires_in: 300}
    end

    blob_resource OpenTrack.Storage.Blob
    attachment_resource OpenTrack.Storage.UserAttachment

    has_one_attached :avatar, dependent: :purge
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

    read :sign_in_with_token do
      # In the generated sign in components, we validate the
      # email and password directly in the LiveView
      # and generate a short-lived token that can be used to sign in over
      # a standard controller action, exchanging it for a standard token.
      # This action performs that exchange. If you do not use the generated
      # liveviews, you may remove this action, and set
      # `sign_in_tokens_enabled? false` in the password strategy.

      description "Attempt to sign in using a short-lived sign in token."
      get? true

      argument :token, :string do
        description "The short-lived sign in token."
        allow_nil? false
        sensitive? true
      end

      # validates the provided sign in token and generates a token
      prepare AshAuthentication.Strategy.Password.SignInWithTokenPreparation

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

    policy action([:read, :update_avatar, :attach_avatar, :detach_avatar, :purge_avatar]) do
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
