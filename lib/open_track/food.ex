defmodule OpenTrack.Food do
  @moduledoc "Interfaces for managing a user's private food photo journal."

  use Ash.Domain,
    otp_app: :open_track,
    extensions: [AshPhoenix]

  resources do
    resource OpenTrack.Food.FoodPhoto do
      define :create_food_photo, action: :create, args: [:uploaded_file]
      define :get_food_photo, action: :read, get_by: [:id]
      define :list_food_photos, action: :journal
      define :delete_food_photo, action: :destroy
    end
  end
end
