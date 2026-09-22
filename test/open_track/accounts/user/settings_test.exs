defmodule OpenTrack.Accounts.User.SettingsTest do
  use ExUnit.Case, async: true

  import Ash.Test

  alias OpenTrack.Accounts
  alias OpenTrack.Accounts.User
  alias OpenTrack.Accounts.User.Settings

  setup do
    owner = %User{id: Ash.UUID.generate()}
    other_user = %User{id: Ash.UUID.generate()}

    %{
      owner: owner,
      other_user: other_user,
      settings: %Settings{id: Ash.UUID.generate(), user_id: owner.id}
    }
  end

  describe "create authorization" do
    test "creates settings for the actor without a transactional data layer", %{owner: owner} do
      # Regression: the previous record-filter policy raised CannotFilterCreates.
      # Simple returns a struct; this test does not persist a database record.
      settings =
        Accounts.create_settings!(
          %{target_weight_kg: 70, target_body_fat_percent: 20},
          actor: owner
        )

      assert settings.user_id == owner.id
      assert settings.target_weight_kg == 70.0
      assert settings.target_body_fat_percent == 20.0
      assert settings.id
    end

    test "checks the proposed owner on the changeset", %{owner: owner, other_user: other_user} do
      changeset = Ash.Changeset.for_create(Settings, :create, %{}, actor: owner)

      assert changeset.valid?
      assert Ash.Changeset.get_attribute(changeset, :user_id) == owner.id
      assert Ash.can?(changeset, owner, run_queries?: false)

      # Simulate an incorrect owner assignment by another resource change.
      wrong_owner = Ash.Changeset.force_change_attribute(changeset, :user_id, other_user.id)
      refute Ash.can?(wrong_owner, owner, run_queries?: false)
    end

    test "rejects creation without an actor" do
      changeset = Ash.Changeset.for_create(Settings, :create, %{target_weight_kg: 70})

      assert_has_error(changeset, Ash.Error.Invalid, fn error ->
        match?(%Ash.Error.Changes.InvalidRelationship{relationship: :user}, error)
      end)

      refute Ash.can?(changeset, nil, run_queries?: false)
      assert {:error, _} = Accounts.create_settings(%{target_weight_kg: 70})
    end

    test "does not accept caller-supplied ownership", %{owner: owner, other_user: other_user} do
      result = Accounts.create_settings(%{user_id: other_user.id}, actor: owner)

      assert_has_error(result, Ash.Error.Invalid, fn error ->
        match?(%Ash.Error.Invalid.NoSuchInput{input: :user_id}, error)
      end)
    end
  end

  describe "read authorization" do
    test "only returns settings belonging to the actor", %{
      owner: owner,
      other_user: other_user,
      settings: own_settings
    } do
      other_settings = %Settings{id: Ash.UUID.generate(), user_id: other_user.id}

      # Supply records to the existing Simple data layer; no database is needed.
      results =
        Settings
        |> Ash.Query.for_read(:read, %{}, actor: owner)
        |> Ash.DataLayer.Simple.set_data([own_settings, other_settings])
        |> Ash.read!()

      assert Enum.map(results, & &1.id) == [own_settings.id]
    end

    test "the get interface cannot fetch another user's settings", %{
      owner: owner,
      other_user: other_user,
      settings: settings
    } do
      query = Ash.DataLayer.Simple.set_data(Settings, [settings])

      assert Accounts.get_settings!(settings.id, actor: owner, query: query).id == settings.id

      result = Accounts.get_settings(settings.id, actor: other_user, query: query)

      assert_has_error(result, Ash.Error.Invalid, fn error ->
        match?(%Ash.Error.Query.NotFound{}, error)
      end)
    end

    test "the domain's user lookup preserves ownership filtering", %{
      owner: owner,
      other_user: other_user,
      settings: settings
    } do
      query = Ash.DataLayer.Simple.set_data(Settings, [settings])

      assert Accounts.get_settings_for_user!(owner.id, actor: owner, query: query).id ==
               settings.id

      result = Accounts.get_settings_for_user(owner.id, actor: other_user, query: query)

      assert_has_error(result, Ash.Error.Invalid, fn error ->
        match?(%Ash.Error.Query.NotFound{}, error)
      end)
    end

    test "does not return settings without an actor", %{settings: settings} do
      results =
        Settings
        |> Ash.Query.for_read(:read, %{}, actor: nil)
        |> Ash.DataLayer.Simple.set_data([settings])
        |> Ash.read!()

      assert results == []
    end
  end

  describe "update and destroy authorization" do
    test "the domain's update interface preserves ownership authorization", %{
      owner: owner,
      other_user: other_user,
      settings: settings
    } do
      assert Accounts.can_update_settings?(owner, settings, %{}, run_queries?: false)
      refute Accounts.can_update_settings?(other_user, settings, %{}, run_queries?: false)
      refute Accounts.can_update_settings?(nil, settings, %{}, run_queries?: false)
    end

    for action <- [:update, :destroy] do
      test "#{action} is only authorized for the owner", %{
        owner: owner,
        other_user: other_user,
        settings: settings
      } do
        action = unquote(action)

        assert Ash.can?({settings, action}, owner, run_queries?: false)
        refute Ash.can?({settings, action}, other_user, run_queries?: false)
        refute Ash.can?({settings, action}, nil, run_queries?: false)
      end
    end
  end
end
