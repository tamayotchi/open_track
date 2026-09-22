defmodule OpenTrack.Storage do
  use Ash.Domain,
    otp_app: :open_track

  resources do
    resource OpenTrack.Storage.Blob
    resource OpenTrack.Storage.FoodPhotoAttachment
    resource OpenTrack.Storage.UserAttachment
  end
end
