defmodule YscWeb.Endpoint do
  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :ysc

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  # Base session options - secure flag is conditionally added based on environment
  @base_session_options [
    store: :cookie,
    key: "_ysc_key",
    signing_salt: "54CY4e5T",
    same_site: "Lax"
  ]

  # Session options - in production, secure flag is needed
  # In development, we omit it to allow HTTP connections
  # Uses code_reloading? macro which is available at compile time
  @session_options (if code_reloading? do
                      @base_session_options
                    else
                      Keyword.put(@base_session_options, :secure, true)
                    end)

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [:peer_data, session: @session_options]]

  # Serve webmanifest without digest hash (browsers expect exact filename)
  # This must come first to take precedence over the digested static files
  plug Plug.Static,
    at: "/",
    from: {:ysc, "priv/static"},
    gzip: false,
    only: ~w(site.webmanifest)

  # Serve .well-known directory (for security.txt and other standards)
  plug Plug.Static,
    at: "/.well-known",
    from: {:ysc, "priv/static/.well-known"},
    gzip: false

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :ysc,
    encodings: [{"zstd", ".zst"}],
    gzip: true,
    brotli: true,
    only: YscWeb.static_paths()

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug LiveViewNative.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :ysc
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Stripe.WebhookPlug,
    at: "/webhooks/stripe",
    handler: Ysc.Stripe.WebhookHandler,
    secret: {Application, :get_env, [:stripity_stripe, :webhook_secret]}

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Sentry.PlugContext
  plug RemoteIp
  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options

  # Prometheus metrics endpoint - must be before router
  plug PromEx.Plug, prom_ex_module: Ysc.PromEx, path: "/metrics"

  plug YscWeb.Router
end
