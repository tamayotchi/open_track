defmodule OpenTrack.Food.FoodPhotoTest do
  use ExUnit.Case, async: true

  alias OpenTrack.Accounts.User
  alias OpenTrack.Food.FoodPhoto

  test "generated attachment actions cannot bypass photo ownership" do
    owner = %User{id: Ash.UUID.generate()}
    other_user = %User{id: Ash.UUID.generate()}
    photo = %FoodPhoto{id: Ash.UUID.generate(), user_id: owner.id}

    for {action, params} <- [
          attach_image: %{io: "image bytes", filename: "lunch.jpg"},
          detach_image: %{},
          purge_image: %{}
        ] do
      assert Ash.can?({photo, action, params}, owner, run_queries?: false)
      refute Ash.can?({photo, action, params}, other_user, run_queries?: false)
      refute Ash.can?({photo, action, params}, nil, run_queries?: false)
    end
  end
end
