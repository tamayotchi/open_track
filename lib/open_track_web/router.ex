defmodule OpenTrackWeb.Router do
  use OpenTrackWeb, :router
  import OpenTrackWeb.UserAuth, only: [fetch_current_user: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {OpenTrackWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", OpenTrackWeb do
    pipe_through :browser

    get "/", PageController, :home

    get "/users/log-in", AuthController, :new_session
    post "/users/log-in", AuthController, :sign_in
    get "/users/register", AuthController, :new_registration
    post "/users/register", AuthController, :register
    delete "/users/log-out", AuthController, :sign_out

    get "/app/account", PageController, :profile
    get "/app/journal", PageController, :profile

    live_session :authenticated,
      on_mount: [{OpenTrackWeb.LiveUserAuth, :required}] do
      live "/app", HomeLive, :index
      live "/app/add", AddFoodLive, :new
      live "/app/account/settings", SettingsLive, :edit
      live "/app/account/security", SecurityLive, :index
    end

    live_session :public_profiles,
      on_mount: [{OpenTrackWeb.LiveUserAuth, :optional}] do
      live "/app/profile/:nickname", ProfileLive, :show
    end
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:open_track, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: OpenTrackWeb.Telemetry
    end
  end
end
