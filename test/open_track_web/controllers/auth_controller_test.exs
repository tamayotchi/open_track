defmodule OpenTrackWeb.AuthControllerTest do
  use OpenTrackWeb.ConnCase

  import OpenTrack.Fixtures
  import Phoenix.LiveViewTest, only: [live: 2]

  alias AshAuthentication.{Jwt, TokenResource}
  alias AshAuthentication.Strategy.RememberMe.Plug.Helpers, as: RememberMe
  alias OpenTrack.Accounts.{Token, User}
  alias OpenTrackWeb.UserAuth

  test "login and registration render ordinary POST forms without a LiveView handoff", %{
    conn: conn
  } do
    for route <- ["/users/log-in", "/users/register"] do
      page = get(conn, route)
      document = page |> html_response(200) |> LazyHTML.from_document()

      assert [_] =
               document
               |> LazyHTML.query("#auth-form[action='#{route}'][method='post']")
               |> LazyHTML.to_tree()

      assert [_] =
               document
               |> LazyHTML.query("#auth-form input[name='_csrf_token']")
               |> LazyHTML.to_tree()

      assert [] =
               document
               |> LazyHTML.query(
                 "#session-form, [phx-submit], [phx-trigger-action], [data-phx-main]"
               )
               |> LazyHTML.to_tree()

      assert [_] =
               document
               |> LazyHTML.query("#signup-link[href='/users/register']")
               |> LazyHTML.to_tree()

      assert [_] =
               document
               |> LazyHTML.query("#login-link[href='/users/log-in']")
               |> LazyHTML.to_tree()

      nickname_inputs =
        document
        |> LazyHTML.query("#auth-form input[name='user[nickname]'][required]")
        |> LazyHTML.to_tree()

      if route == "/users/register" do
        assert [_] = nickname_inputs
      else
        assert [] = nickname_inputs
      end

      refute get_session(page, "user_token")
    end
  end

  test "password login rotates the session and loads the actor on HTTP and LiveView", %{
    conn: conn
  } do
    owner = user()

    signed_in =
      conn
      |> init_test_session(%{"anonymous_data" => "discard", "_csrf_token" => "old"})
      |> post("/users/log-in", user: %{email: to_string(owner.email), password: "valid-password"})

    assert redirected_to(signed_in) == "/app"
    assert signed_in.private.plug_session_info == :renew
    refute get_session(signed_in, "anonymous_data")
    refute get_session(signed_in, "_csrf_token")
    assert %User{id: id} = UserAuth.user_from_session(get_session(signed_in))
    assert id == owner.id
    assert UserAuth.valid_session?(get_session(signed_in, "user_token"), owner)
    assert_persistent_session(signed_in)

    loaded = signed_in |> recycle() |> get("/app")
    assert loaded.assigns.current_user.id == owner.id
    assert html_response(loaded, 200)
    assert loaded.private.plug_session_info == :renew
    assert get_session(loaded, "user_token") == get_session(signed_in, "user_token")
    assert_persistent_session(loaded)
    assert {:ok, _, _} = live(recycle(signed_in), "/app")
  end

  test "registration establishes a session and opens the account page", %{conn: conn} do
    registered =
      post(conn, "/users/register",
        user: %{
          email: "registered@example.com",
          nickname: "Registered",
          password: "valid-password",
          password_confirmation: "valid-password"
        }
      )

    assert redirected_to(registered) == "/app"
    assert %User{} = owner = UserAuth.user_from_session(get_session(registered))
    assert to_string(owner.email) == "registered@example.com"
    assert to_string(owner.nickname) == "registered"
    assert UserAuth.valid_session?(get_session(registered, "user_token"), owner)
    assert_persistent_session(registered)
    assert {:ok, _, _} = live(recycle(registered), "/app/profile/#{owner.nickname}")
  end

  test "unknown emails and wrong passwords re-render the same generic error", %{conn: conn} do
    owner = user()

    for email <- [to_string(owner.email), "unknown@example.com"] do
      failed = post(conn, "/users/log-in", user: %{email: email, password: "wrong-password"})
      document = failed |> html_response(422) |> LazyHTML.from_document()
      refute get_session(failed, "user_token")

      assert document
             |> LazyHTML.query("#user_password-errors")
             |> LazyHTML.text()
             |> String.trim() ==
               "Email or password is incorrect"

      assert [^email] =
               document
               |> LazyHTML.query("input[name='user[email]']")
               |> LazyHTML.attribute("value")

      assert_passwords_blank(document)
    end
  end

  test "registration errors re-render the form without returning submitted passwords", %{
    conn: conn
  } do
    owner = user()

    for params <- [
          %{
            email: "invalid-email",
            password: "valid-password",
            password_confirmation: "valid-password"
          },
          %{email: "short@example.com", password: "short", password_confirmation: "short"},
          %{
            email: "mismatch@example.com",
            password: "valid-password",
            password_confirmation: "different-password"
          },
          %{
            email: to_string(owner.email),
            password: "valid-password",
            password_confirmation: "valid-password"
          }
        ] do
      failed = post(conn, "/users/register", user: Map.put(params, :nickname, "new-member"))
      document = failed |> html_response(422) |> LazyHTML.from_document()
      refute get_session(failed, "user_token")

      assert [_] =
               document
               |> LazyHTML.query("#auth-form[action='/users/register']")
               |> LazyHTML.to_tree()

      assert [_ | _] =
               document |> LazyHTML.query("#auth-form [role='alert']") |> LazyHTML.to_tree()

      assert_passwords_blank(document)
    end
  end

  test "missing, blank, malformed and taken nicknames render nickname errors", %{conn: conn} do
    user(%{nickname: "taken"})

    params = %{
      email: "new@example.com",
      password: "valid-password",
      password_confirmation: "valid-password"
    }

    for input <- [
          params | Enum.map(["", "   ", ["nested"], "TAKEN"], &Map.put(params, :nickname, &1))
        ] do
      failed = post(conn, "/users/register", user: input)
      document = failed |> html_response(422) |> LazyHTML.from_document()
      refute get_session(failed, "user_token")

      assert document
             |> LazyHTML.query("#user_nickname-errors")
             |> LazyHTML.text()
             |> String.trim() != ""

      if input[:nickname] == "TAKEN" do
        assert document |> LazyHTML.query("#user_nickname-errors") |> LazyHTML.text() =~
                 "has already been taken"

        assert ["taken"] =
                 document
                 |> LazyHTML.query("input[name='user[nickname]']")
                 |> LazyHTML.attribute("value")
      end

      assert_passwords_blank(document)
    end
  end

  test "login does not accept a nickname in place of an email", %{conn: conn} do
    owner = user(%{nickname: "member"})

    for credentials <- [
          %{email: to_string(owner.nickname), password: "valid-password"},
          %{nickname: to_string(owner.nickname), password: "valid-password"}
        ] do
      failed = post(conn, "/users/log-in", user: credentials)
      assert html_response(failed, 422)
      refute get_session(failed, "user_token")
    end
  end

  test "missing and malformed credential fields return form errors", %{conn: conn} do
    for route <- ["/users/log-in", "/users/register"],
        params <- [
          %{},
          %{user: "invalid"},
          %{user: %{}},
          %{user: %{email: ["nested"], password: %{nested: "value"}}}
        ] do
      failed = post(conn, route, params)
      document = failed |> html_response(422) |> LazyHTML.from_document()
      refute get_session(failed, "user_token")

      assert [_ | _] =
               document |> LazyHTML.query("#auth-form [role='alert']") |> LazyHTML.to_tree()

      assert_passwords_blank(document)
    end
  end

  test "request parameters cannot request a different token type or authentication context", %{
    conn: conn
  } do
    owner = user()

    signed_in =
      post(conn, "/users/log-in", %{
        "token_type" => "sign_in",
        "context" => %{"token_type" => "remember_me"},
        "user" => %{
          "email" => to_string(owner.email),
          "password" => "valid-password",
          "token_type" => "sign_in",
          "context" => %{"token_type" => "remember_me"}
        }
      })

    assert redirected_to(signed_in) == "/app"
    assert UserAuth.valid_session?(get_session(signed_in, "user_token"), owner)
  end

  test "already-authenticated visitors cannot switch accounts by submitting a guest form", %{
    conn: conn
  } do
    owner = user()
    other = user()
    signed_in = log_in(conn, owner)

    for route <- ["/users/log-in", "/users/register"] do
      response =
        post(signed_in, route,
          user: %{
            email: to_string(other.email),
            password: "valid-password",
            password_confirmation: "valid-password"
          }
        )

      assert redirected_to(response) == "/app"
      assert UserAuth.user_from_session(get_session(response)).id == owner.id
      assert get_session(response, "user_token") == get_session(signed_in, "user_token")
    end
  end

  test "old authentication endpoints and the token exchange are no longer exposed", %{conn: conn} do
    for route <- [
          "/auth/user/password/register",
          "/auth/user/password/sign_in",
          "/auth/user/password/sign_in_with_token"
        ] do
      assert conn |> post(route, %{}) |> response(404)
      assert conn |> get(route) |> response(404)
    end
  end

  test "logout revokes session, bearer and remember-me credentials and clears cookies", %{
    conn: conn
  } do
    owner = user()
    {:ok, bearer_token, _} = Jwt.token_for_user(owner)
    {:ok, remember_token, _} = Jwt.token_for_user(owner, %{}, purpose: :remember_me)
    [cookie_name] = RememberMe.all_remember_me_cookie_names(:open_track)

    signed_in = log_in(conn, owner)

    logged_out =
      signed_in
      |> put_req_header("authorization", "Bearer " <> bearer_token)
      |> put_req_cookie(cookie_name, remember_token)
      |> delete("/users/log-out")

    assert redirected_to(logged_out) == "/users/log-in"
    refute get_session(logged_out, "user_token")
    assert logged_out.private.plug_session_info == :renew
    assert logged_out.resp_cookies[cookie_name].max_age == 0

    for token <- [owner.__metadata__.token, bearer_token, remember_token] do
      assert TokenResource.Actions.token_revoked?(Token, token)
    end

    # A copied cookie cannot restore a revoked session.
    assert signed_in |> get("/app") |> redirected_to() == "/users/log-in"
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(signed_in, "/app")
  end

  test "login, registration and logout enforce browser CSRF protection", %{conn: conn} do
    for route <- ["/users/log-in", "/users/register"] do
      assert_error_sent 403, fn ->
        conn |> put_private(:plug_skip_csrf_protection, false) |> post(route, %{})
      end
    end

    assert_error_sent 403, fn ->
      conn |> put_private(:plug_skip_csrf_protection, false) |> delete("/users/log-out")
    end
  end

  test "both ordinary forms can establish a session with real CSRF protection", %{conn: conn} do
    owner = user()

    for {route, params} <- [
          {"/users/log-in", %{email: to_string(owner.email), password: "valid-password"}},
          {"/users/register",
           %{
             email: "csrf-registration@example.com",
             nickname: "csrf-member",
             password: "valid-password",
             password_confirmation: "valid-password"
           }}
        ] do
      page = conn |> put_private(:plug_skip_csrf_protection, false) |> get(route)

      csrf =
        page.resp_body
        |> LazyHTML.from_document()
        |> LazyHTML.query("#auth-form input[name='_csrf_token']")
        |> LazyHTML.attribute("value")
        |> List.first()

      assert is_binary(csrf)

      signed_in =
        page
        |> recycle()
        |> put_private(:plug_skip_csrf_protection, false)
        |> post(route, %{"_csrf_token" => csrf, "user" => params})

      assert redirected_to(signed_in) == "/app"
      assert %User{} = authenticated = UserAuth.user_from_session(get_session(signed_in))
      assert to_string(authenticated.email) == params.email
    end
  end

  test "GET requests only display forms and cannot authenticate or log out", %{conn: conn} do
    owner = user()

    for route <- ["/users/log-in", "/users/register"] do
      page =
        get(conn, route,
          user: %{
            email: to_string(owner.email),
            password: "valid-password",
            password_confirmation: "valid-password"
          }
        )

      assert html_response(page, 200)
      refute get_session(page, "user_token")
    end

    signed_in = log_in(conn, owner)
    assert signed_in |> get("/users/log-out") |> response(404)
    assert UserAuth.valid_session?(get_session(signed_in, "user_token"), owner)
  end

  defp assert_persistent_session(conn) do
    assert %{max_age: max_age, same_site: "Lax"} = conn.resp_cookies["_open_track_key"]

    assert Enum.any?(get_resp_header(conn, "set-cookie"), fn cookie ->
             String.starts_with?(cookie, "_open_track_key=") and
               String.contains?(cookie, "HttpOnly")
           end)

    assert max_age == 400 * 24 * 60 * 60
    assert {:ok, claims, User} = Jwt.verify(get_session(conn, "user_token"), User)
    assert claims["exp"] - claims["iat"] == 36_500 * 24 * 60 * 60

    assert {:ok, [stored]} =
             TokenResource.Actions.get_token(Token, %{jti: claims["jti"], purpose: "user"})

    assert DateTime.to_unix(stored.expires_at) == claims["exp"]
  end

  defp assert_passwords_blank(document) do
    assert [] =
             document
             |> LazyHTML.query("input[type='password'][value]:not([value=''])")
             |> LazyHTML.to_tree()
  end
end
