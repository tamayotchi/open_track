defmodule OpenTrackWeb.LiveUserAuth do
  @moduledoc """
  Authenticate LiveView mounts independently of the HTTP pipeline.

  LiveView receives the Plug session on both its initial render and WebSocket
  connection. We must verify it here too: router plugs do not run for every
  socket mount or subsequent LiveView event.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [redirect: 2, attach_hook: 4]
  alias OpenTrackWeb.UserAuth

  def on_mount(:optional, _params, session, socket) do
    user = UserAuth.user_from_session(session)

    {:cont,
     socket
     |> assign(:current_user, user)
     |> assign(:current_scope, if(user, do: %{actor: user}))}
  end

  def on_mount(:required, _params, session, socket) do
    user = UserAuth.user_from_session(session)

    socket =
      socket
      |> assign(:current_user, user)
      |> assign(:current_scope, if(user, do: %{actor: user}))

    case user do
      nil ->
        {:halt, redirect(socket, to: "/users/log-in")}

      _user ->
        # An already-mounted LiveView must not keep writing after logout
        # or token expiry.
        token = session["user_token"]

        socket =
          socket
          |> attach_hook(:session_event, :handle_event, fn _, _, socket ->
            check_session(socket, token)
          end)
          |> attach_hook(:session_params, :handle_params, fn _, _, socket ->
            check_session(socket, token)
          end)

        {:cont, socket}
    end
  end

  defp check_session(socket, token) do
    if UserAuth.valid_session?(token, socket.assigns.current_user) do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/users/log-in")}
    end
  end
end
