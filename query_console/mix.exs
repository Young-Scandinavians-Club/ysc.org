defmodule QueryConsole.MixProject do
  use Mix.Project

  def project do
    [
      app: :query_console,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def application do
    [
      mod: {QueryConsole.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # 1.8.16: phoenix.js connection-handling races (#6867) and WebSocket
      # close code 1000 is no longer special-cased (#6880). Endpoint.socket/3
      # accepts max_channels_per_transport (default 100). We mount LiveView
      # with websocket + longpoll (app.js longPollFallbackMs: 2500) and keep
      # the default channel cap. Requires phoenix_pubsub ~> 2.4 (lock 2.4.1);
      # we only start {Phoenix.PubSub, name: QueryConsole.PubSub} and do not
      # call subscribe/broadcast ourselves. 1.8.15 replaceTransport
      # detach-before-close is superseded by the Connection class. 1.8.14:
      # LongPoll fetch timers are cleared after success or abort (#6811);
      # VerifiedRoutes :router must be a compile-time module; local path
      # validation is shared. 1.8.13: phoenix.js reconnects after Chrome
      # freeze/resume. 1.8.10: longpoll POST timeout close-and-retry.
      # phx.gen.auth / phx.gen.cert / phx.new unused (Tailwind stays 4.1.7).
      {:phoenix, "~> 1.8.16"},
      # 2.2.1: ArgumentError on wrong-typed Plug.Crypto args no longer puts
      # the secret key base in the stacktrace (EEF-CVE-2026-105963 /
      # GHSA-ffw9-w85g-f2vh). Public sign/verify/encrypt/decrypt and
      # secure_compare APIs are unchanged. Phoenix/Plug still list ~> 2.2,
      # so pin the patched floor.
      {:plug_crypto, "~> 2.2.1", override: true},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      # 0.22.4: Escape comments on Postgrex.stream/4 (EEF-CVE-2026-66838).
      # We use Postgrex.query/start_link and AnalyticsRepo.query, not stream/4
      # or the :comment option. Public query APIs and BinaryExtension are
      # unchanged. Pin the patched floor.
      {:postgrex, "~> 0.22.4"},
      # GHSA-6c27-994x-c52f / CVE-2026-97853: Decimal < 3.1.2 (DoS via
      # unbounded Decimal.round/3 places). 3.2.0 includes that fix plus
      # faster arithmetic. Query Console serializes Postgrex numeric
      # cells with Decimal.to_string/1 (unchanged in 3.2.0). We do not
      # call round/3, compare NaN, or pass a custom Context. ecto and
      # postgrex still list ~> 3.0, so pin the patched floor.
      {:decimal, "~> 3.2.0", override: true},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      # 1.1.33: EEF-CVE-2026-64941 (LOW / GHSA-36m4-rm57-3prf) rejects ASCII
      # tab, LF, CR, and encoded tab (`/%09`) in LiveView redirect /
      # push_navigate / push_patch `:to` paths so `/\t/evil.com` cannot
      # become a scheme-relative open redirect. lotus_web still requires
      # `< 1.2.0`, so stay on 1.1.x. We only pass compile-time `~p` paths
      # (`/auth/ysc`, `/workbooks/:id`); we do not forward user input to
      # `redirect/2`.
      {:phoenix_live_view, "~> 1.1.33"},
      # 0.1.13: EEF-CVE-2026-92106 (LOW) escapes <style>/<script> text inside
      # SVG and MathML on to_html/2 (mutation XSS). We use lazy_html only in
      # tests via LiveViewTest; pin the patched floor.
      {:lazy_html, "~> 0.1.13", only: :test},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      # 1.2.0: tags may be a 1-arity function (supersedes tag_values in docs).
      # tag_values is still supported and emits no deprecation warning. We keep
      # list tags ([:route], [:event]) because QueryConsoleWeb.Telemetry is
      # Phoenix-generated LiveDashboard-style metrics. We do not pass
      # tag_values or a tags function. ConsoleReporter is commented out.
      {:telemetry_metrics, "~> 1.2"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      # 0.3.0: optional :resource_types (defaults [:a, :aaaa], also :srv).
      # Fly 6PN uses AAAA on ${FLY_APP_NAME}.internal; we do not pass :srv.
      # 0.3.1: look up the hostname of a `{basename, query}` tuple instead
      # of passing the tuple to Resolver.lookup/2 (FunctionClauseError on
      # the real resolver). We pass a string query (`DNS_CLUSTER_QUERY`)
      # or `:ignore`, not a tuple, so the fix is unused. Public APIs
      # unchanged.
      {:dns_cluster, "~> 0.3.1"},
      # 1.12.5: EEF-CVE-2026-74836 (HIGH) bounds/cancels HTTP/2 sends blocked on
      # the connection window; EEF-CVE-2026-75484 (MEDIUM) rejects HTTP/2 header
      # values with CR/LF/NUL.
      # 1.13.0/1.13.1: EEF-CVE-2026-105659 (HIGH) bounds HTTP/2 blocked sends by
      # progress so a WINDOW_UPDATE trickle cannot reset the 15s deadline;
      # EEF-CVE-2026-105660 (MEDIUM) validates HTTP/1 absolute-form and
      # authority-form request-target hosts with the same grammar as Host.
      # 1.13.1 reverts the 1.13.0 stale-conn check that broke Phoenix
      # Plug.Parsers error rendering. Requires Thousand Island 1.6 (peername
      # at accept). We use Bandit.PhoenixAdapter (bandit_pid/1 for idle
      # shutdown). Public adapter APIs are unchanged.
      {:bandit, "~> 1.13.1"},
      # 1.11.0: EEF-CVE-2026-91043 (HPACK-indexed cookies bypass decoded
      # max_header_list_size), EEF-CVE-2026-92103 (HTTP/2 frames buffered up to
      # 16 MiB before max_frame_size), EEF-CVE-2026-94194 (chunked framing when
      # chunked is not the final transfer coding). 1.10.1 still covers
      # EEF-CVE-2026-82672. We reach mint through Finch and Req (SSO token
      # POST). Finch still lists mint ~> 1.8, so pin the patched floor.
      {:mint, "~> 1.11.0", override: true},
      # 0.24.0: close HTTP/1 connections after request/response errors
      # before returning them to the pool (stale Mint 1.11 refs after
      # receive timeouts). Also HTTP QUERY method, pool_timeout wait for
      # dynamic HTTP/2 pools, async TLS shutdown. We reach Finch only
      # through Req.post/2 (SSO token exchange); Req starts the Req.Finch
      # pool. We do not use :query, start_pool/3, or SSLKEYLOGFILE. No
      # documented 0.23→0.24 breaking changes. Req lists finch ~> 0.21,
      # so pin the floor as a direct dep like the main app.
      {:finch, "~> 0.24.0"},
      # 0.7.5: put_aws_sigv4 drops generated Authorization / x-amz-* headers
      # before re-signing a retry; 303 See Other becomes GET except HEAD.
      # We only call Req.post/2 with json: for SSO token exchange — no
      # :params, :path_params, :form_multipart, or :aws_sigv4. Token
      # exchange expects 200 (no 303 follow). Pin the patched floor.
      {:req, "~> 0.7.5"},
      {:lotus, "~> 0.16.6"},
      {:lotus_web, "~> 0.14.1"},
      {:cachex, "~> 4.0"},
      {:pg_query_ex, "~> 0.10.0"},
      {:ecto_ulid, "~> 0.3"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet --repo QueryConsole.Repo", "test"],
      "ecto.setup": [
        "ecto.create",
        "ecto.migrate --repo QueryConsole.Repo",
        "run priv/repo/seeds.exs"
      ],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind query_console", "esbuild query_console"],
      "assets.deploy": [
        "tailwind query_console --minify",
        "esbuild query_console --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
