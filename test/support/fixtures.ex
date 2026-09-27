defmodule OpenTrack.Fixtures do
  @moduledoc false
  alias OpenTrack.Accounts

  def user(attrs \\ %{}) do
    params =
      Map.merge(
        %{
          email: "user-#{System.unique_integer([:positive])}@example.com",
          password: "valid-password",
          password_confirmation: "valid-password"
        },
        attrs
      )

    Accounts.register_user!(params, context: %{private: %{ash_authentication?: true}})
  end

  def image_bytes do
    Base.decode64!(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII="
    )
  end

  def upload do
    path = Path.join(System.tmp_dir!(), "open-track-#{Ash.UUID.generate()}.png")
    File.write!(path, image_bytes())
    ExUnit.Callbacks.on_exit(fn -> File.rm(path) end)
    %Plug.Upload{path: path, filename: "food.png", content_type: "image/png"}
  end

  def log_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> OpenTrackWeb.UserAuth.log_in_user(user)
  end
end
