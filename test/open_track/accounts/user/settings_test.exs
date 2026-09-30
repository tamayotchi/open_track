defmodule OpenTrack.Accounts.User.SettingsTest do
  use OpenTrack.DataCase

  import Ash.Test
  import OpenTrack.Fixtures

  alias Ash.Resource.Info
  alias OpenTrack.Accounts

  test "targets persist, update, and clear" do
    owner = user()

    settings =
      Accounts.create_settings!(%{target_weight_kg: 70, target_body_fat_percent: 20},
        actor: owner
      )

    loaded = Accounts.get_user_by_id!(owner.id, actor: owner, load: :settings).settings
    assert loaded.id == settings.id
    assert loaded.user_id == owner.id
    assert loaded.target_weight_kg == 70.0
    assert loaded.target_body_fat_percent == 20.0

    Accounts.update_settings!(settings, %{target_weight_kg: 72.5, target_body_fat_percent: nil},
      actor: owner
    )

    loaded = Accounts.get_user_by_id!(owner.id, actor: owner, load: :settings).settings
    assert loaded.target_weight_kg == 72.5
    assert is_nil(loaded.target_body_fat_percent)
  end

  test "timezone is a stored attribute defaulting to UTC, without calculation loads" do
    owner = user()
    settings = Accounts.create_settings!(%{target_weight_kg: 70}, actor: owner)
    loaded = Accounts.get_user_by_id!(owner.id, actor: owner, load: :settings).settings
    assert settings.timezone == "Etc/UTC"
    assert loaded.timezone == "Etc/UTC"
    assert Info.attribute(settings.__struct__, :timezone)
    assert is_nil(Info.calculation(settings.__struct__, :timezone))
    assert is_nil(Info.attribute(settings.__struct__, :country_code))
  end

  test "timezone persists through the existing settings update and preserves targets" do
    owner = user()

    settings =
      Accounts.create_settings!(%{timezone: "America/Bogota", target_weight_kg: 70}, actor: owner)

    assert settings.timezone == "America/Bogota"

    assert Accounts.get_user_by_id!(owner.id, actor: owner, load: :settings).settings.timezone ==
             "America/Bogota"

    updated =
      Accounts.update_settings!(settings.id, %{timezone: "America/Los_Angeles"}, actor: owner)

    assert updated.timezone == "America/Los_Angeles"
    loaded = Accounts.get_user_by_id!(owner.id, actor: owner, load: :settings).settings
    assert loaded.timezone == "America/Los_Angeles"
    assert loaded.target_weight_kg == 70.0

    Accounts.update_settings!(loaded, %{target_weight_kg: 72}, actor: owner)

    assert Accounts.get_user_by_id!(owner.id, actor: owner, load: :settings).settings.timezone ==
             "America/Los_Angeles"

    Accounts.update_settings!(settings.id, %{timezone: "Etc/UTC"}, actor: owner)
    loaded = Accounts.get_user_by_id!(owner.id, actor: owner, load: :settings).settings
    assert loaded.timezone == "Etc/UTC"
    assert loaded.target_weight_kg == 72.0
  end

  test "timezone is available when loading the settings relationship without a nested calculation" do
    owner = user()
    Accounts.create_settings!(%{timezone: "America/Bogota"}, actor: owner)

    loaded = Accounts.get_user_by_id!(owner.id, actor: owner, load: [:settings])
    assert loaded.settings.timezone == "America/Bogota"
  end

  test "blank or nil timezone inputs cannot change persisted settings" do
    owner = user()
    settings = Accounts.create_settings!(%{timezone: "America/Bogota"}, actor: owner)

    for zone <- ["", nil] do
      for result <- [
            Accounts.create_settings(%{timezone: zone}, actor: user()),
            Accounts.update_settings(settings.id, %{timezone: zone}, actor: owner)
          ] do
        assert_has_error(result, Ash.Error.Invalid, fn error ->
          match?(%Ash.Error.Changes.InvalidAttribute{field: :timezone}, error) or
            match?(%Ash.Error.Changes.Required{field: :timezone}, error)
        end)
      end
    end

    assert Accounts.get_user_by_id!(owner.id, actor: owner, load: :settings).settings.timezone ==
             "America/Bogota"
  end

  test "timezone names are no longer checked against IANA by settings actions" do
    owner = user()
    settings = Accounts.create_settings!(%{timezone: "Custom/Zone"}, actor: owner)
    assert settings.timezone == "Custom/Zone"

    Accounts.update_settings!(settings.id, %{timezone: "Another/Zone"}, actor: owner)

    assert Accounts.get_user_by_id!(owner.id, actor: owner, load: :settings).settings.timezone ==
             "Another/Zone"
  end

  test "country is no longer accepted as an action input" do
    owner = user()
    settings = Accounts.create_settings!(%{}, actor: owner)

    for result <- [
          Accounts.create_settings(%{country_code: "CO"}, actor: user()),
          Accounts.update_settings(settings.id, %{country_code: "CO"}, actor: owner)
        ] do
      assert_has_error(result, Ash.Error.Invalid, fn error ->
        match?(%Ash.Error.Invalid.NoSuchInput{input: :country_code}, error)
      end)
    end

    assert Accounts.get_user_by_id!(owner.id, actor: owner, load: :settings).settings.timezone ==
             "Etc/UTC"
  end

  test "timezone updates retain owner-only authorization" do
    owner = user()
    settings = Accounts.create_settings!(%{}, actor: owner)
    params = %{timezone: "America/Bogota"}
    assert Accounts.can_update_settings?(owner, settings, params)

    for actor <- [user(), nil] do
      refute Accounts.can_update_settings?(actor, settings, params)
      result = Accounts.update_settings(settings, params, actor: actor)

      if actor do
        assert_has_error(result, Ash.Error.Invalid, &match?(%Ash.Error.Changes.StaleRecord{}, &1))
      else
        assert {:error, %Ash.Error.Forbidden{}} = result
      end
    end

    assert Accounts.get_user_by_id!(owner.id, actor: owner, load: :settings).settings.timezone ==
             "Etc/UTC"
  end

  test "each user can have only one settings record" do
    owner = user()
    settings = Accounts.create_settings!(%{}, actor: owner)

    assert_has_error(Accounts.create_settings(%{}, actor: owner), Ash.Error.Invalid, fn error ->
      match?(%Ash.Error.Changes.InvalidAttribute{field: :user_id}, error)
    end)

    assert Accounts.get_user_by_id!(owner.id, actor: owner, load: :settings).settings.id ==
             settings.id
  end

  test "settings cannot be read or updated by another user or an anonymous caller" do
    owner = user()
    settings = Accounts.create_settings!(%{target_weight_kg: 70}, actor: owner)

    for actor <- [user(), nil] do
      assert_has_error(
        Accounts.get_user_by_id(owner.id, actor: actor, load: :settings),
        Ash.Error.Invalid,
        &match?(%Ash.Error.Query.NotFound{}, &1)
      )

      result = Accounts.update_settings(settings, %{target_weight_kg: 60}, actor: actor)

      if actor do
        # Atomic updates apply the ownership filter and match no record for another user.
        assert_has_error(result, Ash.Error.Invalid, &match?(%Ash.Error.Changes.StaleRecord{}, &1))
      else
        assert {:error, %Ash.Error.Forbidden{}} = result
      end
    end

    assert Accounts.get_user_by_id!(owner.id, actor: owner, load: :settings).settings.target_weight_kg ==
             70.0
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

    loaded = Accounts.get_user_by_id!(owner.id, actor: owner, load: :settings).settings
    assert loaded.target_weight_kg == 70.0
    assert loaded.target_body_fat_percent == 20.0
  end
end
