defmodule OpenTrack.AccountsTest do
  use ExUnit.Case, async: true

  alias OpenTrack.Accounts
  alias OpenTrack.Accounts.User

  setup do
    user = %User{
      id: Ash.UUID.generate(),
      email: Ash.CiString.new("user-#{System.unique_integer([:positive])}@example.com")
    }

    other_user = %User{
      id: Ash.UUID.generate(),
      email: Ash.CiString.new("user-#{System.unique_integer([:positive])}@example.com")
    }

    %{user: user, query: Ash.DataLayer.Simple.set_data(User, [user, other_user])}
  end

  # These tests check interface dispatch and filters, not authentication policies.
  # Records are supplied in memory; no persistence data layer is required.
  test "looks up users by ID through the domain", %{user: user, query: query} do
    result = Accounts.get_user_by_id!(user.id, query: query, authorize?: false)

    assert result.id == user.id
  end

  test "looks up users by email through the domain", %{user: user, query: query} do
    result = Accounts.get_user_by_email!(to_string(user.email), query: query, authorize?: false)

    assert result.id == user.id
  end
end
