defmodule OpenTrack.Storage do
  @moduledoc "Internal domain for AshStorage blob and attachment resources."

  use Ash.Domain,
    otp_app: :open_track

  resources do
    resource OpenTrack.Storage.Blob
    resource OpenTrack.Storage.FoodPhotoAttachment
    resource OpenTrack.Storage.UserAttachment
  end
end
