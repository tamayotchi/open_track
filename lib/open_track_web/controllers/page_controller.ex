defmodule OpenTrackWeb.PageController do
  use OpenTrackWeb, :controller

  def home(conn, _params) do
    user = conn.assigns[:current_user]
    render(conn, :home, current_scope: if(user, do: %{actor: user}), page_title: "Open Track")
  end
end
