defmodule OpenTrackWeb.PersistentSessionTest do
  use OpenTrackWeb.ConnCase

  import OpenTrack.Fixtures
  import Phoenix.LiveViewTest, only: [live: 2]

  alias AshAuthentication.{Info, Jwt}
  alias OpenTrack.Accounts.User

  @cookie_key "_open_track_key"
  @session_max_age 365 * 24 * 60 * 60

  test "login and registration issue persistent cookies matching the token lifetime", %{
    conn: conn
  } do
    owner = user()

    for {path, params} <- [
          {"/users/log-in", %{email: to_string(owner.email), password: "valid-password"}},
          {"/users/register",
           %{
             email: "persistent-registration@example.com",
             nickname: "persistent-registration",
             password: "valid-password",
             password_confirmation: "valid-password"
           }}
        ] do
      signed_in = post(conn, path, user: params)
      assert redirected_to(signed_in) == "/app"
      assert signed_in.resp_cookies[@cookie_key].max_age == @session_max_age

      header = session_cookie_header(signed_in)
      assert header =~ "max-age=#{@session_max_age}"
      assert header =~ "; expires="
      assert header =~ "; path=/"
      assert header =~ "; HttpOnly"
      assert header =~ "; SameSite=Lax"

      assert {365, :days} = Info.authentication_tokens_token_lifetime!(User)
      assert {:ok, claims, User} = Jwt.verify(get_session(signed_in, "user_token"), User)
      assert abs(claims["exp"] - claims["iat"] - @session_max_age) <= 1
    end
  end

  test "a fresh HTTP and LiveView connection restores the login from only the saved cookie", %{
    conn: conn
  } do
    owner = user()
    signed_in = sign_in(conn, owner)
    cookie = signed_in.resp_cookies[@cookie_key].value
    token = get_session(signed_in, "user_token")

    # No init_test_session or recycled connection: model reopening the app with
    # only the persisted cookie from the previous browser session.
    reopened = build_conn() |> put_req_cookie(@cookie_key, cookie) |> get("/app")
    assert html_response(reopened, 200)
    assert reopened.assigns.current_user.id == owner.id
    assert get_session(reopened, "user_token") == token
    assert reopened.private.plug_session_info == :renew
    assert reopened.resp_cookies[@cookie_key].max_age == @session_max_age
    assert session_cookie_header(reopened) =~ "max-age=#{@session_max_age}"

    assert {:ok, _, _} =
             build_conn() |> put_req_cookie(@cookie_key, cookie) |> live("/app")
  end

  test "invalid sessions are cleared rather than renewed", %{conn: conn} do
    owner = user()

    {:ok, expired, _} =
      Jwt.token_for_user(owner, %{"exp" => System.system_time(:second) - 60})

    for token <- [expired, "invalid-token"] do
      rejected = conn |> init_test_session(%{"user_token" => token}) |> get("/app")

      assert redirected_to(rejected) == "/users/log-in"
      refute get_session(rejected, "user_token")
      refute rejected.private.plug_session_info == :renew
    end
  end

  test "logout still rejects a saved persistent cookie on HTTP and LiveView", %{conn: conn} do
    signed_in = sign_in(conn, user())
    cookie = signed_in.resp_cookies[@cookie_key].value
    logged_out = delete(signed_in, "/users/log-out")
    assert redirected_to(logged_out) == "/users/log-in"
    refute get_session(logged_out, "user_token")

    assert build_conn()
           |> put_req_cookie(@cookie_key, cookie)
           |> get("/app")
           |> redirected_to() == "/users/log-in"

    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             build_conn() |> put_req_cookie(@cookie_key, cookie) |> live("/app")
  end

  test "persistent cookies retain the Secure flag on HTTPS requests", %{conn: conn} do
    owner = user()

    signed_in =
      post(conn, "https://www.example.com/users/log-in",
        user: %{email: to_string(owner.email), password: "valid-password"}
      )

    assert signed_in.resp_cookies[@cookie_key].max_age == @session_max_age
    assert signed_in.resp_cookies[@cookie_key].secure
    assert session_cookie_header(signed_in) =~ "; secure"
  end

  defp sign_in(conn, owner) do
    post(conn, "/users/log-in",
      user: %{email: to_string(owner.email), password: "valid-password"}
    )
  end

  defp session_cookie_header(conn) do
    conn
    |> get_resp_header("set-cookie")
    |> Enum.find(&String.starts_with?(&1, @cookie_key <> "="))
  end
end
