defmodule OpenTrack.Accounts.FollowTest do
  use OpenTrack.DataCase

  import OpenTrack.Fixtures
  alias OpenTrack.Accounts

  test "follows are directional, unique, and reflected in public counts" do
    alice = user()
    bob = user()
    carol = user()

    assert counts(alice) == {0, 0}
    follow = Accounts.follow_user!(bob.id, actor: alice)
    assert Accounts.follow_user!(bob.id, actor: alice).id == follow.id
    Accounts.follow_user!(bob.id, actor: carol)
    Accounts.follow_user!(carol.id, actor: bob)

    assert counts(alice) == {0, 1}
    assert counts(bob) == {2, 1}
    assert counts(carol) == {1, 1}

    for actor <- [nil, alice, bob, carol] do
      profile =
        Accounts.get_public_profile!(bob.nickname,
          actor: actor,
          load: [:followers_count, :following_count]
        )

      assert {profile.followers_count, profile.following_count} == {2, 1}
      assert %Ash.NotLoaded{} = profile.follower_connections
      assert %Ash.NotLoaded{} = profile.following_connections
    end

    assert :ok = Accounts.unfollow_user(follow.id, actor: alice)
    assert counts(alice) == {0, 0}
    assert counts(bob) == {1, 1}
  end

  test "both counts load in the profile query without multiplying connections" do
    owner = user()
    empty = user()

    for other <- [user(), user()] do
      Accounts.follow_user!(owner.id, actor: other)
      Accounts.follow_user!(other.id, actor: owner)
    end

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
      for {profile, expected} <- [{owner, {2, 2}}, {empty, {0, 0}}] do
        assert counts(profile) == expected
        assert_receive {^ref, sql}
        assert sql =~ ~s(FROM "users")
        assert sql =~ "LEFT OUTER JOIN"
        assert sql =~ "GROUP BY"
        refute_receive {^ref, _}
      end
    after
      :telemetry.detach(handler)
    end
  end

  def record_query(_event, _measurements, metadata, {pid, ref}) do
    send(pid, {ref, metadata.query})
  end

  test "only the follower can read or remove their connection" do
    alice = user()
    bob = user()
    visitor = user()
    follow = Accounts.follow_user!(bob.id, actor: alice)

    for actor <- [nil, bob, visitor] do
      assert {:error, _} = Accounts.unfollow_user(follow.id, actor: actor)
      assert Accounts.get_follow!(bob.id, actor: actor, not_found_error?: false) == nil
    end

    assert Accounts.get_follow!(bob.id, actor: alice).id == follow.id
    assert {:error, _} = Accounts.follow_user(bob.id)
    assert {:error, _} = Accounts.follow_user(bob.id, %{follower_id: alice.id}, actor: visitor)
    assert counts(bob) == {1, 0}
  end

  test "self follows and missing targets are rejected" do
    alice = user()
    assert {:error, _} = Accounts.follow_user(alice.id, actor: alice)
    assert {:error, _} = Accounts.follow_user(Ash.UUID.generate(), actor: alice)
    assert {:error, _} = Accounts.follow_user(nil, actor: alice)
    assert counts(alice) == {0, 0}
  end

  defp counts(user) do
    profile =
      Accounts.get_public_profile!(user.nickname,
        load: [:followers_count, :following_count]
      )

    {profile.followers_count, profile.following_count}
  end
end
