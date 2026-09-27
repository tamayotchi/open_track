defmodule OpenTrack.Accounts do
  @moduledoc "Account authentication, profile, and settings interfaces."

  use Ash.Domain,
    otp_app: :open_track,
    extensions: [AshPhoenix]

  resources do
    resource OpenTrack.Accounts.Token

    resource OpenTrack.Accounts.User do
      define :register_user, action: :register_with_password
      define :sign_in, action: :sign_in_with_password
      define :change_user_password, action: :change_password
      define :get_user_by_id, action: :read, get_by: [:id]
      define :get_user_by_email, action: :get_by_email, args: [:email]
      define :update_user_avatar, action: :update_avatar, args: [:uploaded_avatar]
      define :remove_user_avatar, action: :purge_avatar
    end

    resource OpenTrack.Accounts.User.Settings do
      define :get_settings, action: :read, get_by: [:id]
      define :get_settings_for_user, action: :read, get_by: [:user_id]
      define :create_settings, action: :create
      define :update_settings, action: :update
    end
  end
end
