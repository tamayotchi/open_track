defmodule OpenTrack.Accounts.User.SettingsTest do
  use OpenTrack.DataCase

  import Ash.Test
  import OpenTrack.Fixtures

  alias OpenTrack.Accounts

  test "targets persist, update, and clear" do
    owner = user()

    settings =
      Accounts.create_settings!(%{target_weight_kg: 70, target_body_fat_percent: 20},
        actor: owner
      )

    loaded = Accounts.get_settings_for_user!(owner.id, actor: owner)
    assert loaded.id == settings.id
    assert loaded.user_id == owner.id
    assert loaded.target_weight_kg == 70.0
    assert loaded.target_body_fat_percent == 20.0

    Accounts.update_settings!(settings, %{target_weight_kg: 72.5, target_body_fat_percent: nil},
      actor: owner
    )

    loaded = Accounts.get_settings!(settings.id, actor: owner)
    assert loaded.target_weight_kg == 72.5
    assert is_nil(loaded.target_body_fat_percent)
  end

  test "each user can have only one settings record" do
    owner = user()
    settings = Accounts.create_settings!(%{}, actor: owner)

    assert_has_error(Accounts.create_settings(%{}, actor: owner), Ash.Error.Invalid, fn error ->
      match?(%Ash.Error.Changes.InvalidAttribute{field: :user_id}, error)
    end)

    assert Accounts.get_settings_for_user!(owner.id, actor: owner).id == settings.id
  end

  test "settings cannot be read or updated by another user or an anonymous caller" do
    owner = user()
    settings = Accounts.create_settings!(%{target_weight_kg: 70}, actor: owner)

    for actor <- [user(), nil] do
      for result <- [
            Accounts.get_settings(settings.id, actor: actor),
            Accounts.get_settings_for_user(owner.id, actor: actor)
          ] do
        assert_has_error(result, Ash.Error.Invalid, &match?(%Ash.Error.Query.NotFound{}, &1))
      end

      result = Accounts.update_settings(settings, %{target_weight_kg: 60}, actor: actor)

      if actor do
        # Atomic updates apply the ownership filter and match no record for another user.
        assert_has_error(result, Ash.Error.Invalid, &match?(%Ash.Error.Changes.StaleRecord{}, &1))
      else
        assert {:error, %Ash.Error.Forbidden{}} = result
      end
    end

    assert Accounts.get_settings!(settings.id, actor: owner).target_weight_kg == 70.0
  end

  test "creation derives ownership from the actor" do
    assert_has_error(Accounts.create_settings(%{}), Ash.Error.Invalid, fn error ->
      match?(%Ash.Error.Changes.InvalidRelationship{relationship: :user}, error)
    end)

    assert_has_error(
      Accounts.create_settings(%{user_id: Ash.UUID.generate()}, actor: user()),
      Ash.Error.Invalid,
      &match?(%Ash.Error.Invalid.NoSuchInput{input: :user_id}, &1)
    )
  end

  test "target constraints apply to creation and updates without changing saved values" do
    owner = user()

    settings =
      Accounts.create_settings!(%{target_weight_kg: 70, target_body_fat_percent: 20},
        actor: owner
      )

    for {field, value} <- [
          {:target_weight_kg, 0},
          {:target_weight_kg, 201},
          {:target_body_fat_percent, 0},
          {:target_body_fat_percent, 100}
        ] do
      params = %{field => value}

      for result <- [
            Accounts.create_settings(params, actor: user()),
            Accounts.update_settings(settings, params, actor: owner)
          ] do
        assert_has_error(result, Ash.Error.Invalid, fn error ->
          match?(%Ash.Error.Changes.InvalidAttribute{field: ^field}, error)
        end)
      end
    end

    loaded = Accounts.get_settings!(settings.id, actor: owner)
    assert loaded.target_weight_kg == 70.0
    assert loaded.target_body_fat_percent == 20.0
  end
end
