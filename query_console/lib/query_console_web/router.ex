defmodule QueryConsoleWeb.Router do
  use QueryConsoleWeb, :router

  import QueryConsoleWeb.UserAuth
  import QueryConsoleWeb.LotusMount

  # In releases Mix is not available; default to production behavior.
  @is_prod (if Code.ensure_loaded?(Mix) do
              Mix.env() == :prod
            else
              true
            end)

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {QueryConsoleWeb.Layouts, :root}
    plug :protect_from_forgery

    # Redirect HTTP → HTTPS and set HSTS in production (Fly terminates TLS;
    # rewrite_on trusts X-Forwarded-Proto). Skip in dev/test to avoid redirect loops.
    if @is_prod do
      plug Plug.SSL, rewrite_on: [:x_forwarded_proto], max_age: 31_536_000
    end

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

    lotus_dashboard("/",
      as: :lotus_dashboard,
      resolver: QueryConsoleWeb.LotusResolver,
      on_mount: [{QueryConsoleWeb.UserAuth, :ensure_authenticated}],
      features: [:timeout_options]
    )
  end
end
