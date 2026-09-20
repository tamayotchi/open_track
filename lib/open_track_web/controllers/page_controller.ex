defmodule OpenTrackWeb.PageController do
  use OpenTrackWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
