defmodule OpenTrack.Food do
  use Ash.Domain,
    otp_app: :open_track

  resources do
    resource OpenTrack.Food.FoodPhoto do
      define :create_food_photo, action: :create, args: [:uploaded_file]
      define :get_food_photo, action: :read, get_by: [:id]
    end
  end
end
