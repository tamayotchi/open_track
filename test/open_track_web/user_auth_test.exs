defmodule OpenTrackWeb.UserAuthTest do
  use OpenTrackWeb.ConnCase

  import OpenTrack.Fixtures
  import Phoenix.LiveViewTest

  alias AshAuthentication.{Jwt, TokenResource}
  alias OpenTrack.Accounts.{Token, User}
  alias OpenTrackWeb.UserAuth

  test "all private routes require authentication", %{conn: conn} do
    for path <- [
          "/app",
          "/app/journal",
          "/app/add",
          "/app/account",
          "/app/account/settings",
          "/app/account/security"
        ] do
      assert conn |> get(path) |> redirected_to() == "/users/log-in"
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, path)
    end
  end

  test "HTTP and LiveView reject malformed and forged session credentials", %{conn: conn} do
    owner = user()

    for session <- [
          %{"user_id" => owner.id},
          %{"user" => AshAuthentication.user_to_subject(owner)},
          %{"user_token" => "fake"},
          %{"user_token" => ["not-a-string"]},
          %{"user_token" => owner.__metadata__.token <> "tampered"}
        ] do
      refute UserAuth.user_from_session(session)
      guest = init_test_session(conn, session)
      rejected = get(guest, "/app")
      assert redirected_to(rejected) == "/users/log-in"
      refute rejected.assigns.current_user
      refute get_session(rejected, "user_token")
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(guest, "/app")
    end
  end

  test "the session requires a persisted, unexpired user token", %{conn: conn} do
    owner = user()

    {:ok, expired, _} =
      Jwt.token_for_user(owner, %{"exp" => System.system_time(:second) - 60})

    # Intentionally bypass token persistence to test that a valid signature alone
    # is insufficient. Normal application code issues tokens via Ash actions.
    {:ok, unstored, _} =
      Joken.generate_and_sign(
        Jwt.Config.default_claims(User),
        %{"sub" => AshAuthentication.user_to_subject(owner)},
        Jwt.Config.token_signer(User)
      )

    assert {:ok, _, User} = Jwt.verify(unstored, User)

    for token <- [expired, unstored] do
      refute UserAuth.valid_session?(token, owner)
      refute UserAuth.user_from_session(%{"user_token" => token})
      guest = init_test_session(conn, %{"user_token" => token})
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(guest, "/app")
      assert guest |> get("/app") |> redirected_to() == "/users/log-in"
    end
  end

  test "purpose-scoped and impersonation tokens cannot become browser sessions" do
    owner = user()

    # Even a valid JWT stored as a normal token must have a session purpose.
    for claims <- [
          %{"purpose" => "sign_in"},
          %{"purpose" => "remember_me"},
          %{"act" => %{"sub" => "another-user"}}
        ] do
      {:ok, token, _} = Jwt.token_for_user(owner, claims)
      refute UserAuth.user_from_session(%{"user_token" => token})
      refute UserAuth.valid_session?(token, owner)
    end
  end

  test "mounted-session checks bind the token to the original actor and respect revocation" do
    owner = user()
    other = user()
    token = owner.__metadata__.token

    assert UserAuth.valid_session?(token, owner)
    refute UserAuth.valid_session?(token, other)
    refute UserAuth.valid_session?(token, nil)
    assert :ok = TokenResource.Actions.revoke(Token, token)
    refute UserAuth.valid_session?(token, owner)
    refute UserAuth.user_from_session(%{"user_token" => token})
  end

  test "authenticated visitors are redirected away from login and registration pages", %{
    conn: conn
  } do
    signed_in = log_in(conn, user())

    for route <- ["/users/log-in", "/users/register"] do
      assert signed_in |> get(route) |> redirected_to() == "/app"
    end
  end
end
