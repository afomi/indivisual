defmodule IndivisualWeb.Router do
  use IndivisualWeb, :router

  import IndivisualWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {IndivisualWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", IndivisualWeb do
    pipe_through :browser

    get "/", PageController, :home

    # ALB target-group health check. Must stay OUT of force_ssl's redirect
    # (see config/prod.exs) or the target group never goes healthy.
    get "/healthz", PageController, :healthz

    # The two features indivisual is focused on.
    get "/topo", PageController, :topo
    get "/topo/:space_slug", PageController, :topo
    live "/atlas", AtlasLive, :index
  end

  # GitHub OAuth — sign-in and the repo grant that backs file persistence.
  scope "/auth", IndivisualWeb do
    pipe_through :browser

    get "/:provider", OAuthController, :request
    get "/:provider/callback", OAuthController, :callback
  end

  # Other scopes may use custom stacks.
  # scope "/api", IndivisualWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:indivisual, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: IndivisualWeb.Telemetry
    end
  end

  ## Authentication routes

  scope "/", IndivisualWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
  end

  scope "/", IndivisualWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email
  end

  scope "/", IndivisualWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
