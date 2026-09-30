defmodule OpenTrack.PublicProfilesTest do
  use OpenTrack.DataCase

  import OpenTrack.Fixtures
  import OpenTrack.AnalysisFixtures

  alias OpenTrack.{Accounts, Food}

  setup do
    configure_ai()
    %{owner: user(%{nickname: "juantamayo26"}), visitor: user()}
  end

  test "public lookup is case-insensitive and does not select credentials", %{owner: owner} do
    profile = Accounts.get_public_profile!("JUANTAMAYO26", load: :avatar_url)
    assert profile.id == owner.id
    assert to_string(profile.nickname) == "juantamayo26"
    refute Ash.Resource.selected?(profile, :email)
    refute Ash.Resource.selected?(profile, :hashed_password)
    assert %Ash.NotLoaded{} = profile.email
    assert %Ash.NotLoaded{} = profile.hashed_password
    assert Accounts.get_public_profile!("missing", not_found_error?: false) == nil
  end

  test "public reads stay scoped to the requested owner, regardless of the viewer", %{
    owner: owner,
    visitor: visitor
  } do
    Accounts.create_settings!(%{target_weight_kg: 72}, actor: owner)
    Accounts.create_settings!(%{target_weight_kg: 90}, actor: visitor)
    stub_prediction()
    photo = create_analyzed_photo(owner)
    create_analyzed_photo(visitor)
    pending = create_unanalyzed_photo(owner)
    from = DateTime.add(DateTime.utc_now(), -86_400)
    until = DateTime.add(DateTime.utc_now(), 86_400)

    for actor <- [nil, visitor, owner] do
      profile = Accounts.get_public_profile!("juantamayo26", actor: actor)
      assert profile.public_settings.target_weight_kg == 72

      page =
        Food.list_food_photos!(owner.id,
          actor: actor,
          page: [limit: 24, count: true],
          load: :image_url
        )

      assert page.count == 2
      assert Enum.sort(Enum.map(page.results, & &1.id)) == Enum.sort([photo.id, pending.id])
      assert Enum.all?(page.results, &is_binary(&1.image_url))
      assert [entry] = Food.nutrition_chart_data!(owner.id, from, until, actor: actor)
      assert entry.id == photo.id
      assert entry.analysis["total_calories"] == 520
      assert Food.nutrition_chart_data!(owner.id, until, DateTime.add(until, 86_400)) == []
    end

    for user_id <- [nil, "not-a-uuid"] do
      assert {:error, %Ash.Error.Invalid{}} = Food.list_food_photos(user_id, page: [limit: 24])
      assert {:error, %Ash.Error.Invalid{}} = Food.nutrition_chart_data(user_id, from, until)
    end

    assert {:error, _} = Accounts.get_public_profile(nil)
  end

  test "profile and settings use one joined query, including profiles without settings", %{
    owner: owner,
    visitor: visitor
  } do
    Accounts.create_settings!(
      %{target_weight_kg: 72, target_body_fat_percent: 18, timezone: "America/Bogota"},
      actor: owner
    )

    ref = make_ref()
    handler = {__MODULE__, ref}

    :ok =
      :telemetry.attach(
        handler,
        [:open_track, :repo, :query],
        &__MODULE__.record_query/4,
        {self(), ref}
      )

    try do
      for actor <- [nil, visitor, owner] do
        profile = Accounts.get_public_profile!("JUANTAMAYO26", actor: actor)

        assert profile.public_settings == %{
                 target_weight_kg: 72.0,
                 target_body_fat_percent: 18.0,
                 timezone: "America/Bogota"
               }

        assert_receive {^ref, sql}
        assert sql =~ ~s(FROM "users")
        assert sql =~ ~s(LEFT OUTER JOIN "settings")
        refute_receive {^ref, _}
      end

      owner_profile =
        Accounts.get_user_by_id!(owner.id, actor: owner, load: :public_settings)

      assert owner_profile.public_settings == %{
               target_weight_kg: 72.0,
               target_body_fat_percent: 18.0,
               timezone: "America/Bogota"
             }

      assert_receive {^ref, sql}
      assert sql =~ ~s(FROM "users")
      assert sql =~ ~s(LEFT OUTER JOIN "settings")
      refute_receive {^ref, _}

      profile = Accounts.get_public_profile!(visitor.nickname)
      assert profile.id == visitor.id

      assert profile.public_settings == %{
               target_weight_kg: nil,
               target_body_fat_percent: nil,
               timezone: nil
             }

      assert_receive {^ref, sql}
      assert sql =~ ~s(LEFT OUTER JOIN "settings")
      refute_receive {^ref, _}

      assert Accounts.get_public_profile!("missing", not_found_error?: false) == nil
      assert_receive {^ref, _sql}
      refute_receive {^ref, _}
    after
      :telemetry.detach(handler)
    end
  end

  def record_query(_event, _measurements, metadata, {pid, ref}) do
    send(pid, {ref, metadata.query})
  end

  test "publicly readable records still cannot be changed by visitors", %{
    owner: owner,
    visitor: visitor
  } do
    settings = Accounts.create_settings!(%{target_weight_kg: 72}, actor: owner)
    photo = create_unanalyzed_photo(owner)
    profile = Accounts.get_public_profile!("juantamayo26")

    for actor <- [nil, visitor] do
      assert {:error, _} = Food.delete_food_photo(photo.id, actor: actor)

      assert {:error, _} =
               Accounts.update_settings(settings, %{target_weight_kg: 99}, actor: actor)

      assert {:error, _} = Accounts.update_user_avatar(profile, upload(), actor: actor)
    end

    assert Food.get_food_photo!(photo.id, actor: owner).id == photo.id
    assert Accounts.get_public_profile!("juantamayo26").public_settings.target_weight_kg == 72
  end
end
