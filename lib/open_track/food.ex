defmodule OpenTrack.Food do
  @moduledoc "Interfaces for managing food journals and viewing public profiles."

  use Ash.Domain,
    otp_app: :open_track,
    extensions: [AshPhoenix]

  resources do
    resource OpenTrack.Food.FoodPhoto do
      define :create_food_photo, action: :create, args: [:uploaded_file]
      define :get_food_photo, action: :read, get_by: [:id]
      define :list_food_photos, action: :for_profile, args: [:user_id]
      define :list_followed_users_photos, action: :from_followed_users
      define :delete_food_photo, action: :destroy

      define :nutrition_chart_data,
        action: :nutrition_chart_data,
        args: [:user_id, :from, :until]
    end

    resource OpenTrack.Food.Analysis do
      define :analyze_food_photo, action: :analyze, args: [:photo_id]
    end
  end
end
