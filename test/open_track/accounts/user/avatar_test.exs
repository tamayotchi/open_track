defmodule OpenTrack.Accounts.User.AvatarTest do
  use OpenTrack.DataCase

  import Ash.Test
  import OpenTrack.Fixtures

  alias OpenTrack.Accounts
  alias OpenTrack.Storage.{Blob, UserAttachment}

  test "avatars persist across reloads and replacement and removal purge old files" do
    owner = user()
    assert is_nil(Accounts.get_user_by_id!(owner.id, actor: owner, load: :avatar).avatar)

    Accounts.update_user_avatar!(owner, upload(), actor: owner)
    loaded = Accounts.get_user_by_id!(owner.id, actor: owner, load: [avatar: :blob])
    assert loaded.avatar.blob.filename == "food.png"
    assert AshStorage.Operations.download(loaded.avatar.blob) == {:ok, image_bytes()}

    Accounts.update_user_avatar!(owner, upload(), actor: owner)
    replacement = Accounts.get_user_by_id!(owner.id, actor: owner, load: [avatar: :blob])
    refute replacement.avatar.blob.id == loaded.avatar.blob.id
    assert AshStorage.Operations.download(replacement.avatar.blob) == {:ok, image_bytes()}
    assert_purged(loaded.avatar)

    Accounts.remove_user_avatar!(owner, actor: owner)
    assert is_nil(Accounts.get_user_by_id!(owner.id, actor: owner, load: :avatar).avatar)
    assert_purged(replacement.avatar)
  end

  test "avatar updates and removals cannot bypass ownership" do
    owner = user()
    file = upload()
    Accounts.update_user_avatar!(owner, file, actor: owner)
    original = Accounts.get_user_by_id!(owner.id, actor: owner, load: [avatar: :blob])

    for actor <- [user(), nil] do
      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.update_user_avatar(owner, file, actor: actor)

      assert {:error, %Ash.Error.Forbidden{}} = Accounts.remove_user_avatar(owner, actor: actor)
    end

    loaded = Accounts.get_user_by_id!(owner.id, actor: owner, load: [avatar: :blob])
    assert loaded.avatar.id == original.avatar.id
    assert AshStorage.Operations.download(loaded.avatar.blob) == {:ok, image_bytes()}
  end

  test "avatar uploads require a file and cannot change account fields" do
    owner = user()

    for {file, error_type} <- [
          {nil, Ash.Error.Changes.Required},
          {123, Ash.Error.Changes.InvalidArgument}
        ] do
      assert_has_error(
        Accounts.update_user_avatar(owner, file, actor: owner),
        Ash.Error.Invalid,
        fn error ->
          error.__struct__ == error_type and error.field == :uploaded_avatar
        end
      )
    end

    assert_has_error(
      Accounts.update_user_avatar(owner, upload(), %{email: "new@example.com"}, actor: owner),
      Ash.Error.Invalid,
      &match?(%Ash.Error.Invalid.NoSuchInput{input: :email}, &1)
    )
  end

  test "generated attachment actions cannot bypass avatar ownership" do
    owner = %Accounts.User{id: Ash.UUID.generate()}
    other = %Accounts.User{id: Ash.UUID.generate()}

    for {action, params} <- [
          attach_avatar: %{io: "avatar bytes", filename: "avatar.jpg"},
          detach_avatar: %{},
          purge_avatar: %{}
        ] do
      assert Ash.can?({owner, action, params}, owner, run_queries?: false)
      refute Ash.can?({owner, action, params}, other, run_queries?: false)
      refute Ash.can?({owner, action, params}, nil, run_queries?: false)
    end
  end

  defp assert_purged(attachment) do
    # Internal storage resources have no application code interfaces.
    assert is_nil(Ash.get!(UserAttachment, attachment.id, not_found_error?: false))
    assert is_nil(Ash.get!(Blob, attachment.blob.id, not_found_error?: false))
    assert {:error, :not_found} = AshStorage.Operations.download(attachment.blob)
  end
end
