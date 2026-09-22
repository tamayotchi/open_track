# OpenTrack

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## File storage (AshStorage + Cloudflare R2)

The resource declarations are wired together as follows:

```text
OpenTrack.Food.FoodPhoto                   owner and food-analysis results
  └── image: Storage.FoodPhotoAttachment  food_photo_id + blob_id, name: "image"
        └── blob: Storage.Blob           key, filename, content_type, size, checksum
              └── R2 object              the actual image bytes

OpenTrack.Accounts.User               avatar owner
  └── avatar: Storage.UserAttachment  user_id + blob_id, name: "avatar"
        └── blob: Storage.Blob        the same Blob resource, a different record
              └── R2 object           the actual avatar bytes
```

Start with these files:

- `lib/open_track/food/food_photo.ex`: `has_one_attached :image` and the create action.
- `lib/open_track/storage/food_photo_attachment.ex`: explicit relationships to FoodPhoto and Blob.
- `lib/open_track/storage/blob.ex`: shared AshStorage-generated file metadata; key uniqueness lives here.
- `lib/open_track/accounts/user.ex`: `has_one_attached :avatar` and the update action.
- `lib/open_track/storage/user_attachment.ex`: explicit relationships to User and Blob.

Separate attachment resources keep each owner foreign key required: food attachments
must have `food_photo_id`, and avatar attachments must have `user_id`. Both use the
same Blob resource, but ordinary uploads create separate blob records and files.

**There is no persistence data layer on these resources yet.** No `ash_sqlite`,
other database adapter, or migrations were added. R2 stores files, not the Ash
records: add persistence for User, FoodPhoto, Blob, FoodPhotoAttachment, and UserAttachment
before using real uploads. Configure their foreign keys and unique identities too.
Otherwise uploads can leave objects in R2 without durable metadata.
The tests check resource declarations, input validation, owner policies, and avatar
relationship/URL loading using supplied in-memory records; they do not perform
an end-to-end upload, replacement, or purge.

### R2 configuration

AshStorage is pinned to a Git revision because it is not yet released on Hex.
It requires Elixir 1.17+. Its S3 service uses the included `req_s3` dependency.

The per-resource `service` declarations in `FoodPhoto` and `User`'s `storage do`
blocks configure R2 for their attachments. There is no R2 configuration in
`config/runtime.exs`. The bucket name is fixed as `"open-track"`; create that
private bucket in your Cloudflare account before uploading. The S3 service uses
`prefix: "food/"` for food photos and `prefix: "avatars/"` for user avatars.
Objects live under `food/<generated-key>` or `avatars/<generated-key>` inside the
same bucket. No folder needs to be created manually; the prefix is part of the object key.

Set `R2_ACCOUNT_ID` **before compiling**. Credentials are read later by the S3
adapter, so they must be available when performing storage operations:

```sh
export R2_ACCOUNT_ID="your-cloudflare-account-id"
export R2_ACCESS_KEY_ID="your-r2-access-key-id"
export R2_SECRET_ACCESS_KEY="your-r2-secret-access-key"
```

Keep the bucket private. Image URLs are signed GET URLs, valid for five minutes;
they are calculated when loaded, not stored in the database. Only credential
**environment-variable names**, never the secrets, are persisted in blob options.
If `R2_ACCOUNT_ID` is absent during compilation, no real storage service is
configured. After setting or changing it, recompile with `mix compile --force`
(and rebuild your release when deploying). Changing it only at application
startup does not update the compiled DSL settings. No bucket environment variable
is required.

Tests override the resource-level service with `AshStorage.Service.Test`, even
when the resource was compiled with R2 settings. No R2 environment variables or
real credentials are required to run the tests.

### Creating a photo (after adding persistence)

```elixir
upload = %Plug.Upload{
  path: "/tmp/lunch.jpg",
  filename: "lunch.jpg",
  content_type: "image/jpeg"
}

photo = OpenTrack.Food.create_food_photo!(upload, actor: current_user)

photo =
  OpenTrack.Food.get_food_photo!(photo.id,
    actor: current_user,
    load: [:image_url, image: :blob]
  )

photo.image.blob.key      # Generated key; the S3 service prepends "food/" in R2
photo.image.blob.filename # "lunch.jpg"
photo.image_url           # Short-lived signed download URL
```

The create action requires an image and derives `user_id` from the actor.
`AshStorage.Changes.AttachFile` handles the upload and creates Blob/FoodPhotoAttachment
records, forwarding the action context. FoodPhoto policies restrict reads and
attachment actions to its owner. Storage resources are internal; do not expose
raw blob or attachment actions as public endpoints without their own authorization.
Before adding upload endpoints, also implement server-side file type/size
validation (a client-supplied MIME type is not proof of image content).

AshStorage generates `attach_image`, `detach_image`, and `purge_image` actions.
Replacing the image purges the old file; destroying the FoodPhoto also purges its
attachment. Database and R2 writes are not one atomic transaction, so production
upload handling will also need failure/orphan cleanup.

### User avatars (after adding persistence)

Avatar actions live on User; their application interfaces live on Accounts:

```elixir
upload = %Plug.Upload{
  path: "/tmp/avatar.jpg",
  filename: "avatar.jpg",
  content_type: "image/jpeg"
}

user = OpenTrack.Accounts.update_user_avatar!(current_user, upload, actor: current_user)

user =
  OpenTrack.Accounts.get_user_by_id!(user.id,
    actor: current_user,
    load: [:avatar_url, avatar: :blob]
  )

user.avatar.blob.filename # "avatar.jpg"
user.avatar_url           # Short-lived signed download URL

OpenTrack.Accounts.remove_user_avatar!(user, actor: current_user)
```

The update action requires `uploaded_avatar` and maps it to the `avatar` attachment.
It accepts no account attributes, so an upload cannot change an email or password.
A user may have no avatar; removing one uses AshStorage's `purge_avatar` action,
which removes its attachment, blob, and stored file. Uploading a replacement purges
the previous avatar through AshStorage's single-attachment behavior.

Only the owner may read their user record through the standard read action or run
avatar upload, attach, detach, and purge actions. Existing AshAuthentication
interactions retain their authentication bypass. Avatars are private in this first
implementation; public profiles would need a separate, carefully scoped read API.

This is backend wiring only: no upload UI or endpoint is added. As with food
photos, add server-side image-content and size validation, persistence, and
failure/orphan cleanup before exposing uploads. The file argument validates a
file input, not that its bytes are a safe image. Do not call internal storage
resource actions directly from a public endpoint.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
