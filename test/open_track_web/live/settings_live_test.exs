defmodule OpenTrackWeb.SettingsLiveTest do
  use OpenTrackWeb.ConnCase
  import Phoenix.LiveViewTest
  import OpenTrack.Fixtures
  alias OpenTrack.Accounts

  test "Account opens the owned profile and settings return to that same profile", %{conn: conn} do
    owner = user()
    conn = log_in(conn, owner)
    path = "/app/profile/#{owner.nickname}"
    {:ok, home, _} = live(conn, "/app")

    {:ok, profile, _} =
      home |> element("#nav-account") |> render_click() |> follow_redirect(conn, path)

    assert has_element?(profile, "#nav-account[aria-current='page'][href='#{path}']")
    assert has_element?(profile, "#profile-avatar-placeholder")
    assert has_element?(profile, "#profile-followers dd", "0")
    assert has_element?(profile, "#profile-following dd", "0")
    refute has_element?(profile, "#targets-form")
    refute has_element?(profile, "#account-email")

    {:ok, settings, _} =
      profile
      |> element("#profile-settings-link")
      |> render_click()
      |> follow_redirect(conn, "/app/account/settings")

    assert has_element?(settings, "#targets-form")
    assert has_element?(settings, "#timezone-form")
    assert has_element?(settings, "#avatar-form")
    assert has_element?(settings, "#account-email", to_string(owner.email))
    assert has_element?(settings, "#back-to-profile[href='#{path}']")
    assert has_element?(settings, "#nav-account[data-active='true']")

    {:ok, security, _} =
      settings
      |> element("#account-security-link")
      |> render_click()
      |> follow_redirect(conn, "/app/account/security")

    assert has_element?(security, "#password-form")
    assert has_element?(security, "#back-to-settings[href='/app/account/settings']")
  end

  test "target form persists updates and blank values across remounts", %{conn: conn} do
    owner = user()
    conn = log_in(conn, owner)
    {:ok, view, _} = live(conn, "/app/account/settings")
    assert has_element?(view, "#account-email", to_string(owner.email))

    view
    |> form("#targets-form", targets: %{target_weight_kg: "70.5", target_body_fat_percent: "20"})
    |> render_submit()

    assert has_element?(view, "#flash-info", "Targets saved.")
    {:ok, reloaded, _} = live(conn, "/app/account/settings")
    assert has_element?(reloaded, "input[name='targets[target_weight_kg]'][value='70.5']")
    assert has_element?(reloaded, "input[name='targets[target_body_fat_percent]'][value='20.0']")

    reloaded |> form("#targets-form", targets: %{target_weight_kg: "201"}) |> render_change()
    assert has_element?(reloaded, "#targets-form [role='alert']")
    reloaded |> form("#targets-form", targets: %{target_weight_kg: "201"}) |> render_submit()
    assert has_element?(reloaded, "#targets-form [role='alert']")

    assert Accounts.get_user_by_id!(owner.id, actor: owner, load: :public_settings).public_settings.target_weight_kg ==
             70.5

    reloaded
    |> form("#targets-form", targets: %{target_weight_kg: "", target_body_fat_percent: ""})
    |> render_submit()

    settings =
      Accounts.get_user_by_id!(owner.id, actor: owner, load: :public_settings).public_settings

    assert is_nil(settings.target_weight_kg)
    assert is_nil(settings.target_body_fat_percent)
    {:ok, cleared, _} = live(conn, "/app/account/settings")
    refute has_element?(cleared, "#targets-form input[value]:not([value=''])")
  end

  test "password changes keep the current and other devices' sessions usable", %{conn: conn} do
    owner = user()
    signed_in = log_in(conn, owner)

    other_login =
      Accounts.sign_in!(
        %{email: to_string(owner.email), password: "valid-password"},
        context: %{private: %{ash_authentication?: true}}
      )

    other_device = log_in(conn, other_login)
    refute get_session(signed_in, "user_token") == get_session(other_device, "user_token")
    {:ok, view, _} = live(signed_in, "/app/account/security")
    {:ok, other_view, _} = live(other_device, "/app/account/settings")

    view
    |> form("#password-form",
      password: %{
        current_password: "valid-password",
        password: "new-password",
        password_confirmation: "new-password"
      }
    )
    |> render_submit()

    assert has_element?(view, "#flash-info", "Password updated.")
    assert has_element?(view, "#password-form")
    refute has_element?(view, "#password-form input[type='password'][value]:not([value=''])")
    assert {:ok, _, _} = live(signed_in, "/app")
    assert {:ok, _, _} = live(other_device, "/app")

    other_view
    |> form("#targets-form", targets: %{target_weight_kg: "70"})
    |> render_submit()

    assert Accounts.get_user_by_id!(owner.id, actor: owner, load: :public_settings).public_settings.target_weight_kg ==
             70.0
  end

  test "password forms require the latest password even in an already-open tab", %{conn: conn} do
    owner = user()
    signed_in = log_in(conn, owner)
    {:ok, view, _} = live(signed_in, "/app/account/security")
    {:ok, other_tab, _} = live(signed_in, "/app/account/security")
    opts = [context: %{private: %{ash_authentication?: true}}]

    view
    |> form("#password-form",
      password: %{
        current_password: "valid-password",
        password: "new-password",
        password_confirmation: "new-password"
      }
    )
    |> render_submit()

    other_tab
    |> form("#password-form",
      password: %{
        current_password: "valid-password",
        password: "another-password",
        password_confirmation: "another-password"
      }
    )
    |> render_submit()

    refute has_element?(other_tab, "#flash-info")
    assert has_element?(other_tab, "#password-form", "Current password is incorrect")

    assert {:error, _} =
             Accounts.sign_in(%{email: to_string(owner.email), password: "valid-password"}, opts)

    assert {:ok, _} =
             Accounts.sign_in(%{email: to_string(owner.email), password: "new-password"}, opts)

    for {current_password, password} <- [
          {"new-password", "another-password"},
          {"another-password", "latest-password"}
        ] do
      other_tab
      |> form("#password-form",
        password: %{
          current_password: current_password,
          password: password,
          password_confirmation: password
        }
      )
      |> render_submit()

      assert has_element?(other_tab, "#flash-info", "Password updated.")

      assert {:ok, _} =
               Accounts.sign_in(%{email: to_string(owner.email), password: password}, opts)
    end
  end

  test "already-mounted pages reject events after session revocation", %{conn: conn} do
    owner = user()
    signed_in = log_in(conn, owner)
    {:ok, view, _} = live(signed_in, "/app/account/settings")
    delete(signed_in, "/users/log-out")
    render_submit(view, "save-targets", %{"targets" => %{"target_weight_kg" => "70"}})
    assert_redirect(view, "/users/log-in")

    assert is_nil(Accounts.get_user_by_id!(owner.id, actor: owner, load: :settings).settings)
  end

  test "already-mounted pages reject navigation after session revocation", %{conn: conn} do
    signed_in = log_in(conn, user())
    {:ok, view, _} = live(signed_in, "/app")
    delete(signed_in, "/users/log-out")
    render_patch(view, "/app?range=30")
    assert_redirect(view, "/users/log-in")
  end

  test "incomplete avatar uploads can be cancelled without crashing", %{conn: conn} do
    {:ok, view, _} = live(log_in(conn, user()), "/app/account/settings")

    input =
      file_input(view, "#avatar-form", :avatar, [
        %{name: "avatar.png", content: image_bytes(), type: "image/png"}
      ])

    preflight_upload(input)
    render_submit(view, "save-avatar", %{})
    assert has_element?(view, "#flash-error")
    view |> element("button[phx-click='cancel-avatar']") |> render_click()
    refute has_element?(view, "button[phx-click='cancel-avatar']")
  end

  test "LiveView rejects large and unsupported uploads without replacing the avatar", %{
    conn: conn
  } do
    owner = user()
    Accounts.update_user_avatar!(owner, upload(), actor: owner)
    original = Accounts.get_user_by_id!(owner.id, actor: owner, load: [avatar: :blob])
    {:ok, view, _} = live(log_in(conn, owner), "/app/account/settings")

    for entry <- [
          %{name: "notes.txt", content: "text", type: "text/plain"},
          %{name: "large.png", content: :binary.copy(<<0>>, 8_000_001), type: "image/png"}
        ] do
      input = file_input(view, "#avatar-form", :avatar, [entry])
      preflight_upload(input)
      assert has_element?(view, "#avatar-form [role='alert']")
      render_submit(view, "save-avatar", %{})
      loaded = Accounts.get_user_by_id!(owner.id, actor: owner, load: [avatar: :blob])
      assert loaded.avatar.id == original.avatar.id
      assert {:ok, bytes} = AshStorage.Operations.download(loaded.avatar.blob)
      assert bytes == image_bytes()
      view |> element("button[phx-click='cancel-avatar']") |> render_click()
    end
  end

  test "avatar upload and removal persist and the browser receives its storage URL", %{conn: conn} do
    owner = user()
    conn = log_in(conn, owner)
    {:ok, view, _} = live(conn, "/app/account/settings")

    input =
      file_input(view, "#avatar-form", :avatar, [
        %{name: "avatar.png", content: image_bytes(), type: "image/png"}
      ])

    render_upload(input, "avatar.png")
    view |> form("#avatar-form") |> render_submit()
    assert has_element?(view, "#remove-avatar")
    profile = Accounts.get_user_by_id!(owner.id, actor: owner, load: :avatar_url)
    assert is_binary(profile.avatar_url)
    assert has_element?(view, "#account-avatar-image[src='#{profile.avatar_url}']")
    {:ok, account, _} = live(conn, "/app/profile/#{owner.nickname}")

    assert has_element?(
             account,
             "#profile-avatar[src='#{profile.avatar_url}'][width='112'][height='112']"
           )

    refute has_element?(account, "#profile-avatar-placeholder")
    assert has_element?(account, ".profile-connections #profile-followers")
    {:ok, reloaded, _} = live(conn, "/app/account/settings")
    assert has_element?(reloaded, "#account-avatar-image[src='#{profile.avatar_url}']")
    view |> element("#remove-avatar") |> render_click()
    refute has_element?(view, "#remove-avatar")
    refute has_element?(view, "#account-avatar-image")
    {:ok, without_avatar, _} = live(conn, "/app/account/settings")
    refute has_element?(without_avatar, "#account-avatar-image")
  end
end
