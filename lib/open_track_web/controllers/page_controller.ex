defmodule OpenTrackWeb.PageController do
  use OpenTrackWeb, :controller

  def profile(conn, _params) do
    case conn.assigns.current_user do
      nil -> redirect(conn, to: ~p"/users/log-in")
      user -> redirect(conn, to: ~p"/app/profile/#{user.nickname}")
    end
  end

  def home(conn, _params) do
    user = conn.assigns[:current_user]
    render(conn, :home, current_scope: if(user, do: %{actor: user}), page_title: "Open Track")
  end
end
