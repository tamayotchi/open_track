defmodule AppNameWeb.PageController do
  use AppNameWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
