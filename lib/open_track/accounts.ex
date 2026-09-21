defmodule OpenTrack.Accounts do
  use Ash.Domain,
    otp_app: :open_track

  resources do
    resource OpenTrack.Accounts.Token
    resource OpenTrack.Accounts.User
    resource OpenTrack.Accounts.User.Settings
  end
end
