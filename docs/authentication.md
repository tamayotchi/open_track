# How authentication works

This application deliberately does **not** use `ash_authentication_phoenix` for
now, so the Phoenix integration is visible in application code. This is a
learning exercise, not a recommendation to maintain a custom integration forever;
see [TODO.md](../TODO.md).

We still use **AshAuthentication** for credential checking, password hashing,
token issuance/verification and revocation.
**AshPhoenix** builds forms from Ash actions. We are not implementing cryptography
or password storage ourselves.

## Login and registration, step by step

```text
Browser                              AuthController / Ash actions
   |                                             |
   |-- GET /users/log-in or /users/register ----->|
   |<----------------------------- ordinary form |
   |                                             |
   |-- POST credentials + CSRF token ----------->|
   |                         verify / register account
   |                         issue normal session JWT
   |                         renew session       |
   |<-------------------- Set-Cookie + /app redirect
   |
   |-- GET /app --> HTTP session loader --> LiveView mount
   |-- WebSocket connection -------------> LiveView mount again
```

1. [`AuthController`](../lib/open_track_web/controllers/auth_controller.ex)
   renders an ordinary HTML form through `AuthHTML`. Both pages use the domain's
   `Accounts.form_to_register_user/1` or `form_to_sign_in/1` interface.
2. Each form POSTs to its own page URL: `/users/register` or `/users/log-in`.
   The controller submits the AshPhoenix form using server-built authentication
   context. Request parameters cannot select an action, context, or token type.
3. The Ash action registers the account or checks the credentials and returns a
   user with a normal session JWT. Invalid submissions re-render the same form
   with HTTP 422 and validation errors; password inputs are always cleared.
4. [`UserAuth.log_in_user/2`](../lib/open_track_web/user_auth.ex) clears old session
   and CSRF state, renews the session, and writes the JWT under `"user_token"`.
   Plug writes the signed, HTTP-only session cookie with the redirect response.
   A bare user ID is never accepted as authentication.
5. The next request loads the user from that cookie. Journal and settings pages
   still use LiveView; authentication forms do not require a WebSocket.

There is no temporary sign-in token, hidden handoff form, or token-exchange
endpoint. The password strategy sets `sign_in_tokens_enabled? false`. Normal
session tokens and their database records remain necessary.

AshAuthentication generates `register_with_password` and `sign_in_with_password`
from the `password :password` strategy. The domain interfaces call these generated
actions; `register_action_accept [:nickname]` adds nickname to the registration
inputs. The custom `change_password` action remains explicit so it can require
the current password.

Registration requires a non-blank nickname, stored trimmed and lowercase. An Ash
identity and database unique index prevent duplicate nicknames, including case
variants. Nicknames are reserved for future social features; login still accepts
only an email and password.

## Stay signed in by default

Login and registration issue tokens valid for 36,500 days (approximately 100
years). AshAuthentication requires a finite lifetime, so this is effectively
non-expiring for normal use, not a removal of expiry validation. Existing tokens
keep their original expiry; sign out and back in once to obtain the new lifetime.

The signed, HTTP-only, SameSite=Lax session cookie persists across browser
restarts. Its 400-day lifetime is renewed on each authenticated HTTP request,
without changing the JWT or bypassing revocation. LiveView events alone cannot
refresh a cookie. Browser retention limits, clearing cookies, private browsing,
or more than 400 days without an HTTP visit can still require signing in again.

This favors convenience over automatic credential expiry: a stolen session can
remain usable until revoked. Logout still revokes the token server-side, and
password changes alone still do not revoke other sessions.

## Session checks in HTTP and LiveView

[`router.ex`](../lib/open_track_web/router.ex) uses ordinary Phoenix routes and
`live_session` blocks:

- **HTTP:** the browser pipeline fetches the session, enforces CSRF protection,
  then calls `UserAuth.fetch_current_user/2` to identify the current user.
  `AuthController` redirects already-authenticated visitors away from login and
  registration pages and submissions to `/app`.
- **LiveView:** `LiveUserAuth.on_mount/4` independently loads the user from the
  session for both disconnected and connected mounts. Router plugs are not run
  for every socket mount. The hook assigns `current_user` and
  `current_scope: %{actor: user}`. Protected pages reject guests.

Both loaders require a JWT with a valid signature and expiry **and** a matching,
non-expired persisted token with purpose `"user"`. The JWT's own purpose is
checked too; sign-in, remember-me, and impersonation tokens cannot be used as
browser sessions. The token's subject is resolved through AshAuthentication.
Resource policies still authorize all user-owned actions; route guards do not
replace those policies.

Photo and avatar URLs are generated during owner-authorized reads using
AshStorage's URL calculations. The browser fetches the bytes directly from R2,
not from an application controller. A signed URL remains usable by anyone who
has it until its five-minute expiry, even after the app session is logged out.

## Logout, password changes, and existing tabs

`DELETE /users/log-out` is CSRF-protected. `UserAuth.log_out_user/1` uses core
AshAuthentication helpers to revoke the session and any bearer/remember-me
credentials supplied in the request, remove remember-me cookies, and clear/renew
the browser session. Just deleting the cookie would leave a stolen copy usable.

Password changes update the password without revoking existing sessions or
extending their lifetime. The password page stays open and clears the form after
success. It reloads the user before each submission so another tab's password
change is respected. Existing sessions remain usable until token expiry or
logout (provided the browser retains its cookie). Consequently, changing a
password alone does not invalidate a stolen session token. The optional
`log_out_everywhere` add-on is not enabled.

A mounted LiveView keeps its own assigns. Therefore `LiveUserAuth` attaches
**event and navigation hooks** that recheck the JWT, its stored token, and its
subject against the mounted actor. Revoked or expired sessions redirect at the
next event/navigation; this is not an immediate broadcast disconnect of all tabs.

The current forms do not need a remember-me checkbox: the normal session cookie
is persistent by default. There is no separate remember-me-token restoration.
Remember-me issuance metadata, when present, and logout cleanup continue to use
core AshAuthentication helpers.

## Small integration details now owned by us

- The authentication form maps `AuthenticationFailed` to a generic password-field
  error. This error translation previously came from the Phoenix integration.
- Session rotation and CSRF state clearing are explicit in `UserAuth`.
- Every authentication POST and logout stays inside the browser CSRF pipeline.
- Passwords and tokens remain filtered from request logs. Do not log form inputs,
  session maps, or authentication errors that contain credentials.

Regression tests live in `test/open_track_web/controllers/auth_controller_test.exs`,
`test/open_track_web/user_auth_test.exs`, and
`test/open_track_web/live/account_live_test.exs`. They cover real credentials,
form validation, invalid/expired/unpersisted tokens, CSRF enforcement, session
rotation, logout, password changes, and already-mounted views. Signed image URL
coverage is in `test/open_track_web/live/signed_images_test.exs`.
