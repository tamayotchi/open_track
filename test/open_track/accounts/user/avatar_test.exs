defmodule OpenTrack.Accounts.User.AvatarTest do
  use ExUnit.Case, async: true

  import Ash.Test

  alias OpenTrack.Accounts
  alias OpenTrack.Accounts.User
  alias OpenTrack.Food.FoodPhoto
  alias OpenTrack.Storage.{Blob, UserAttachment}

  setup do
    owner = %User{id: Ash.UUID.generate()}
    other_user = %User{id: Ash.UUID.generate()}

    %{
      owner: owner,
      other_user: other_user,
      uploaded_avatar: Ash.Type.File.from_path("/tmp/avatar.jpg"),
      query: Ash.DataLayer.Simple.set_data(User, [owner, other_user])
    }
  end

  test "shares blob metadata with food photos but uses a separate attachment resource" do
    assert AshStorage.Info.storage_blob_resource!(User) == Blob
    assert AshStorage.Info.storage_blob_resource!(FoodPhoto) == Blob
    assert AshStorage.Info.storage_attachment_resource!(User) == UserAttachment
    refute AshStorage.Info.storage_attachment_resource!(FoodPhoto) == UserAttachment

    assert {:ok, %{type: :one, dependent: :purge}} = AshStorage.Info.attachment(User, :avatar)
    avatar = Ash.Resource.Info.relationship(User, :avatar)
    assert avatar.type == :has_one
    assert avatar.destination == UserAttachment
    assert avatar.destination_attribute == :user_id
    assert Ash.Resource.Info.calculation(User, :avatar_url)
  end

  test "avatar uploads use in-memory test storage, never R2" do
    {:ok, avatar} = AshStorage.Info.attachment(User, :avatar)
    assert is_nil(avatar.service)

    assert AshStorage.Info.service_for_attachment(User, avatar) ==
             {:ok, {AshStorage.Service.Test, []}}
  end

  test "wires the file argument to the avatar attachment without accepting user attributes" do
    action = Ash.Resource.Info.action(User, :update_avatar)
    assert action.accept == []
    argument = Enum.find(action.arguments, &(&1.name == :uploaded_avatar))
    assert argument.type == Ash.Type.File
    refute argument.allow_nil?

    assert Enum.any?(action.changes, fn change ->
             change.change ==
               {AshStorage.Changes.AttachFile, argument: :uploaded_avatar, attachment: :avatar}
           end)
  end

  describe "domain avatar actions" do
    test "allows the owner to upload and remove their avatar", %{
      owner: owner,
      uploaded_avatar: file
    } do
      assert Accounts.can_update_user_avatar?(owner, owner, file, run_queries?: false)
      assert Accounts.can_remove_user_avatar?(owner, owner, run_queries?: false)
    end

    test "requires an uploaded avatar", %{owner: owner} do
      result = Accounts.update_user_avatar(owner, nil, actor: owner)

      assert_has_error(result, Ash.Error.Invalid, fn error ->
        match?(%Ash.Error.Changes.Required{field: :uploaded_avatar}, error)
      end)
    end

    test "rejects invalid file input", %{owner: owner} do
      result = Accounts.update_user_avatar(owner, 123, actor: owner)

      assert_has_error(result, Ash.Error.Invalid, fn error ->
        match?(%Ash.Error.Changes.InvalidArgument{field: :uploaded_avatar}, error)
      end)
    end

    test "does not allow changing account fields through avatar upload", %{
      owner: owner,
      uploaded_avatar: file
    } do
      result =
        Accounts.update_user_avatar(owner, file, %{email: "changed@example.com"}, actor: owner)

      assert_has_error(result, Ash.Error.Invalid, fn error ->
        match?(%Ash.Error.Invalid.NoSuchInput{input: :email}, error)
      end)
    end

    test "rejects uploads and removals by another user or an anonymous caller", %{
      owner: owner,
      other_user: other_user,
      uploaded_avatar: file
    } do
      for actor <- [other_user, nil] do
        refute Accounts.can_update_user_avatar?(actor, owner, file, run_queries?: false)
        refute Accounts.can_remove_user_avatar?(actor, owner, run_queries?: false)

        # Update authorization may re-read the user to apply its ownership filter.
        opts = [actor: actor, context: %{data_layer: %{data: %{User => [owner]}}}]

        assert {:error, %Ash.Error.Forbidden{}} =
                 Accounts.update_user_avatar(owner, file, opts)

        assert {:error, %Ash.Error.Forbidden{}} =
                 Accounts.remove_user_avatar(owner, opts)
      end
    end
  end

  test "generated attachment actions cannot bypass ownership", %{
    owner: owner,
    other_user: other_user
  } do
    for {action, params} <- [
          attach_avatar: %{io: "avatar bytes", filename: "avatar.jpg"},
          detach_avatar: %{},
          purge_avatar: %{}
        ] do
      assert Ash.can?({owner, action, params}, owner, run_queries?: false)
      refute Ash.can?({owner, action, params}, other_user, run_queries?: false)
      refute Ash.can?({owner, action, params}, nil, run_queries?: false)
    end
  end

  describe "reading the user that owns the avatar" do
    test "allows the owner to fetch their own user", %{owner: owner, query: query} do
      assert Accounts.get_user_by_id!(owner.id, actor: owner, query: query).id == owner.id
    end

    test "loads the owner's avatar metadata and URL through the domain", %{owner: owner} do
      blob = %Blob{id: Ash.UUID.generate(), key: "avatar-key", filename: "avatar.jpg"}

      attachment = %UserAttachment{
        id: Ash.UUID.generate(),
        user_id: owner.id,
        blob_id: blob.id,
        name: "avatar"
      }

      # Supply the related records too: this exercises relationship loading,
      # not database persistence or a real upload.
      context = %{
        shared: %{
          data_layer: %{data: %{User => [owner], UserAttachment => [attachment], Blob => [blob]}}
        }
      }

      user =
        Accounts.get_user_by_id!(owner.id,
          actor: owner,
          context: context,
          load: [:avatar_url, avatar: :blob]
        )

      assert user.avatar.id == attachment.id
      assert user.avatar.blob.id == blob.id
      assert user.avatar.blob.filename == "avatar.jpg"
      assert user.avatar_url == "http://test.local/storage/avatar-key"
    end

    test "a user can have no avatar", %{owner: owner} do
      user =
        Accounts.get_user_by_id!(owner.id,
          actor: owner,
          context: %{
            shared: %{data_layer: %{data: %{User => [owner], UserAttachment => [], Blob => []}}}
          },
          load: [:avatar_url, avatar: :blob]
        )

      assert is_nil(user.avatar)
      assert is_nil(user.avatar_url)
    end

    test "does not expose another user's record", %{
      owner: owner,
      other_user: other_user,
      query: query
    } do
      for actor <- [other_user, nil] do
        result = Accounts.get_user_by_id(owner.id, actor: actor, query: query)

        assert_has_error(result, Ash.Error.Invalid, fn error ->
          match?(%Ash.Error.Query.NotFound{}, error)
        end)
      end
    end
  end
end
