defmodule OpenTrack.AccountsTest do
  use OpenTrack.DataCase

  import Ash.Test
  import OpenTrack.Fixtures

  alias OpenTrack.Accounts

  @auth_opts [context: %{private: %{ash_authentication?: true}}]

  test "registration persists a hashed password and unique case-insensitive email" do
    user = user(%{email: "Member@Example.com"})
    loaded = Accounts.get_user_by_id!(user.id, actor: user)
    assert to_string(loaded.email) == "member@example.com"
    assert Bcrypt.verify_pass("valid-password", loaded.hashed_password)

    assert_has_error(
      Accounts.register_user(
        %{
          email: "MEMBER@example.com",
          nickname: "another-member",
          password: "valid-password",
          password_confirmation: "valid-password"
        },
        @auth_opts
      ),
      Ash.Error.Invalid,
      &match?(%Ash.Error.Changes.InvalidAttribute{field: :email}, &1)
    )
  end

  test "registration persists a normalized nickname and rejects duplicates regardless of case" do
    owner = user(%{nickname: "  Member  "})
    loaded = Accounts.get_user_by_id!(owner.id, actor: owner)
    assert to_string(loaded.nickname) == "member"

    for nickname <- ["member", "MEMBER", " Member "] do
      assert_has_error(
        Accounts.register_user(
          %{
            email: "another@example.com",
            nickname: nickname,
            password: "valid-password",
            password_confirmation: "valid-password"
          },
          @auth_opts
        ),
        Ash.Error.Invalid,
        &match?(%Ash.Error.Changes.InvalidAttribute{field: :nickname}, &1)
      )
    end
  end

  test "registration requires a non-blank nickname" do
    params = %{
      email: "member@example.com",
      password: "valid-password",
      password_confirmation: "valid-password"
    }

    for input <- [params | Enum.map([nil, "", "   "], &Map.put(params, :nickname, &1))] do
      assert_has_error(
        Accounts.register_user(input, @auth_opts),
        Ash.Error.Invalid,
        &match?(%Ash.Error.Changes.Required{field: :nickname}, &1)
      )
    end
  end

  test "a nickname cannot be used instead of an email to sign in" do
    owner = user(%{nickname: "member"})

    assert_has_error(
      Accounts.sign_in(%{email: "member", password: "valid-password"}, @auth_opts),
      &match?(%AshAuthentication.Errors.AuthenticationFailed{}, &1)
    )

    assert Accounts.sign_in!(
             %{email: to_string(owner.email), password: "valid-password"},
             @auth_opts
           ).id == owner.id
  end

  test "changing the password requires the current password and replaces the login credential" do
    user = user()

    assert {:ok, signed_in} =
             Accounts.sign_in(
               %{email: to_string(user.email), password: "valid-password"},
               @auth_opts
             )

    assert signed_in.id == user.id

    params = %{password: "new-password", password_confirmation: "new-password"}

    assert_has_error(
      Accounts.change_user_password(user, Map.put(params, :current_password, "wrong"),
        actor: user
      ),
      &match?(%AshAuthentication.Errors.AuthenticationFailed{}, &1)
    )

    Accounts.change_user_password!(user, Map.put(params, :current_password, "valid-password"),
      actor: user
    )

    assert_has_error(
      Accounts.sign_in(%{email: to_string(user.email), password: "valid-password"}, @auth_opts),
      &match?(%AshAuthentication.Errors.AuthenticationFailed{}, &1)
    )

    assert Accounts.sign_in!(
             %{email: to_string(user.email), password: "new-password"},
             @auth_opts
           ).id ==
             user.id
  end

  test "knowing the password does not allow another actor to change it" do
    owner = user()

    params = %{
      current_password: "valid-password",
      password: "new-password",
      password_confirmation: "new-password"
    }

    for actor <- [user(), nil] do
      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.change_user_password(owner, params, actor: actor)
    end

    assert Accounts.sign_in!(
             %{email: to_string(owner.email), password: "valid-password"},
             @auth_opts
           ).id ==
             owner.id
  end

  test "user records and avatar URLs are private" do
    owner = user()

    for actor <- [user(), nil] do
      assert_has_error(
        Accounts.get_user_by_id(owner.id, actor: actor, load: :avatar_url),
        Ash.Error.Invalid,
        &match?(%Ash.Error.Query.NotFound{}, &1)
      )
    end
  end
end
