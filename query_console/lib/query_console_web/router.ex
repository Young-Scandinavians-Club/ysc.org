defmodule QueryConsoleWeb.Router do
  use QueryConsoleWeb, :router

  import QueryConsoleWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {QueryConsoleWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", QueryConsoleWeb do
    pipe_through :browser

    get "/up", UpController, :index
    get "/auth/ysc", AuthController, :ysc
    get "/auth/ysc/callback", AuthController, :callback
    get "/auth/logout", AuthController, :delete
    delete "/auth/logout", AuthController, :delete
    get "/auth/signed-out", AuthController, :signed_out
  end

  scope "/", QueryConsoleWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :authenticated,
      on_mount: [{QueryConsoleWeb.UserAuth, :ensure_authenticated}] do
      live "/", ConsoleLive, :index
      live "/workbooks/:id", ConsoleLive, :show
    end
  end
end
