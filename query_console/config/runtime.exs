import Config

if System.get_env("PHX_SERVER") do
  config :query_console, QueryConsoleWeb.Endpoint, server: true
end

# Lotus AI assistant (OpenRouter / ReqLLM). Off unless OPENROUTER_API_KEY is set.
if api_key = System.get_env("OPENROUTER_API_KEY") do
  config :lotus,
    ai: [
      enabled: true,
      model: System.get_env("LOTUS_AI_MODEL") || "openrouter:moonshotai/kimi-k3",
      api_key: api_key
    ]

  # kimi-k3 catalogs output == context (1_048_576). ReqLLM defaults max_tokens to
  # limits.output when unset, so OpenRouter rejects any non-empty prompt. Cap output
  # so reserved completion tokens leave headroom for input/tools/schema.
  max_tokens =
    case System.get_env("LOTUS_AI_MAX_TOKENS") do
      nil -> 4096
      "" -> 4096
      value -> String.to_integer(value)
    end

  config :llm_db,
    custom: %{
      openrouter: [
        models: %{
          "moonshotai/kimi-k3" => %{
            limits: %{output: max_tokens}
          }
        }
      ]
    }
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  analytics_database_url =
    System.get_env("ANALYTICS_REPLICA_DATABASE_URL") ||
      System.get_env("ANALYTICS_DATABASE_URL") ||
      raise """
      environment variable ANALYTICS_DATABASE_URL (or ANALYTICS_REPLICA_DATABASE_URL) is missing.
      Never rewrite ports to 5433; provide the full analytics connection URL explicitly.
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :query_console, QueryConsole.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  config :query_console, QueryConsole.AnalyticsRepo,
    url: analytics_database_url,
    pool_size: String.to_integer(System.get_env("ANALYTICS_POOL_SIZE") || "2"),
    prepare: :unnamed,
    socket_options: maybe_ipv6

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :query_console, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :query_console, QueryConsoleWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Bind IPv4 any (0.0.0.0) so fly-proxy health checks can reach the app.
      ip: {0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  config :query_console, QueryConsole.SSO,
    authorize_url:
      System.get_env("YSC_SSO_AUTHORIZE_URL") ||
        raise("environment variable YSC_SSO_AUTHORIZE_URL is missing."),
    token_url:
      System.get_env("YSC_SSO_TOKEN_URL") ||
        raise("environment variable YSC_SSO_TOKEN_URL is missing."),
    logout_url: System.get_env("YSC_SSO_LOGOUT_URL"),
    client_id:
      System.get_env("YSC_SSO_CLIENT_ID") ||
        raise("environment variable YSC_SSO_CLIENT_ID is missing."),
    client_secret:
      System.get_env("YSC_SSO_CLIENT_SECRET") ||
        raise("environment variable YSC_SSO_CLIENT_SECRET is missing."),
    redirect_uri:
      System.get_env("YSC_SSO_REDIRECT_URI") ||
        raise("environment variable YSC_SSO_REDIRECT_URI is missing."),
    post_logout_redirect_uri: System.get_env("YSC_SSO_POST_LOGOUT_REDIRECT_URI"),
    base_url:
      System.get_env("QUERY_CONSOLE_BASE_URL") ||
        raise("environment variable QUERY_CONSOLE_BASE_URL is missing.")

  # Exit the BEAM when idle so Fly Machines stop billing CPU/RAM.
  # Set SHUTDOWN_WHEN_INACTIVE_MS=0 to disable. Default: 10 minutes.
  shutdown_when_inactive_ms =
    case System.get_env("SHUTDOWN_WHEN_INACTIVE_MS") do
      nil -> :timer.minutes(10)
      "0" -> nil
      "" -> nil
      value -> String.to_integer(value)
    end

  config :query_console, :shutdown_when_inactive_ms, shutdown_when_inactive_ms
end
