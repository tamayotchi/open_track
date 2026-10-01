defmodule OpenTrack.Accounts.Follow do
  @moduledoc "A directed follow between users. Only counts are public."

  use Ash.Resource,
    otp_app: :open_track,
    domain: OpenTrack.Accounts,
    authorizers: [Ash.Policy.Authorizer],
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "follows"
    repo OpenTrack.Repo

    references do
      reference :follower, on_delete: :delete
      reference :followed, on_delete: :delete
    end

    custom_indexes do
      index [:followed_id]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :follow do
      accept [:followed_id]
      upsert? true
      upsert_identity :unique_follow
      upsert_fields []

      change relate_actor(:follower)

      validate compare(:followed_id, is_not_equal: :follower_id),
        message: "you cannot follow yourself"
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if relating_to_actor(:follower)
    end

    policy action_type([:read, :destroy]) do
      authorize_if expr(follower_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id
  end

  relationships do
    belongs_to :follower, OpenTrack.Accounts.User do
      allow_nil? false
    end

    belongs_to :followed, OpenTrack.Accounts.User do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_follow, [:follower_id, :followed_id]
  end
end
