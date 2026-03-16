defmodule RioWeb.Router do
  use RioWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RioWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", RioWeb do
    pipe_through :browser

    # Redirect root to the mind map
    live "/", MindMapLive.Show, :show

    # Mind Map routes (single global tree)
    live "/node/:id", MindMapLive.Show, :show
    live "/node/:id/new", MindMapLive.Show, :new_child
    live "/node/:id/edit/:node_id", MindMapLive.Show, :edit
  end

  scope "/api", RioWeb.Api do
    pipe_through [:api, RioWeb.Plugs.ApiAuth]

    post "/inbox", InboxController, :create
    post "/inbox/batch", InboxController, :batch_create
    get "/inbox", InboxController, :index
    patch "/inbox/:id", InboxController, :update
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:rio, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: RioWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
