defmodule OpenTrackWeb.UserAuth do
  @moduledoc """
  Our browser-session integration, kept explicit as a learning exercise.

  AshAuthentication still owns password hashing, JWT verification, token storage,
  and revocation. This module connects those primitives to Plug and LiveView.
  See `docs/authentication.md` for the HTTP → WebSocket lifecycle.
  """

  import Plug.Conn

  alias AshAuthentication.{Info, Jwt, TokenResource}
  alias AshAuthentication.Plug.Helpers
  alias AshAuthentication.Strategy.RememberMe.Plug.Helpers, as: RememberMe
  alias OpenTrack.Accounts.{Token, User}

  @session_key "user_token"

  @doc "Load the HTTP actor after Plug has fetched the signed cookie session."
  def fetch_current_user(conn, _opts) do
    user = user_from_session(get_session(conn))

    # Refresh the persistent cookie even when the session contents are unchanged.
    # Only verified sessions are renewed; JWT expiry and revocation still apply.
    conn =
      if user,
        do: configure_session(conn, renew: true),
        else: delete_session(conn, @session_key)

    assign(conn, :current_user, user)
  end

  @doc "Load a user from a session, including on a new LiveView WebSocket connection."
  def user_from_session(session) do
    with {:ok, subject} <- verify_session_token(session[@session_key]),
         {:ok, user} <- AshAuthentication.subject_to_user(subject, User) do
      user
    else
      _ -> nil
    end
  end

  @doc "Recheck mounted views: a valid signature alone does not prove a session is still active."
  def valid_session?(token, %User{} = user) do
    case verify_session_token(token) do
      {:ok, subject} -> subject == AshAuthentication.user_to_subject(user)
      :error -> false
    end
  end

  def valid_session?(_token, _user), do: false

  # Only trusted server code builds this context. Request parameters must never
  # be merged into it: AshAuthentication's policies recognize this interaction.
  def password_context do
    %{
      strategy: Info.strategy!(User, :password),
      private: %{ash_authentication?: true}
    }
  end

  @doc "Write the session in an HTTP response; a LiveView event cannot set a cookie."
  def log_in_user(conn, %User{} = user) do
    conn
    |> renew_session()
    |> put_session(@session_key, user.__metadata__.token)
    |> maybe_put_remember_me_cookie(user)
  end

  @doc "Revoke server-side credentials before forgetting the browser session."
  def log_out_user(conn) do
    conn
    |> RememberMe.delete_all_remember_me_cookies(:open_track)
    |> Helpers.revoke_bearer_tokens(:open_track)
    |> Helpers.revoke_session_tokens(:open_track)
    |> renew_session()
  end

  defp verify_session_token(token) when is_binary(token) do
    with {:ok, %{"sub" => subject, "jti" => jti} = claims, User}
         when is_binary(subject) and is_binary(jti) and not is_map_key(claims, "act") <-
           Jwt.verify(token, User),
         true <- Map.get(claims, "purpose", "user") == "user",
         # Short-lived sign-in tokens and remember-me tokens are not sessions.
         # Logout changes the stored purpose to "revocation".
         {:ok, [%{subject: ^subject}]} <-
           TokenResource.Actions.get_token(Token, %{jti: jti, purpose: "user"}) do
      {:ok, subject}
    else
      _ -> :error
    end
  end

  defp verify_session_token(_), do: :error

  defp renew_session(conn) do
    # Rotate the CSRF state as well as the session; don't carry an anonymous
    # browser's session contents into the authenticated session.
    Plug.CSRFProtection.delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp maybe_put_remember_me_cookie(conn, user) do
    case user.__metadata__ do
      %{remember_me: %{cookie_name: name} = options} ->
        RememberMe.put_remember_me_cookie(conn, to_string(name), options)

      _ ->
        conn
    end
  end
end
