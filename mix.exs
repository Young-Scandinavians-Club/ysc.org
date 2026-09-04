defmodule Ysc.MixProject do
  use Mix.Project

  def project do
    [
      app: :ysc,
      version: "2.37.0",
      elixir: "~> 1.20",
      elixirc_options: elixirc_options_for(Mix.env()),
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader],
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :credo, :stripity_stripe],
        list_unused_filters: true
      ],
      # cowlib still has open EEF advisories with no patched Hex release. Revisit by 2026-10-04.
      # Requires Hex >= 2.5.1-dev for ignore_advisories (see etc/scripts/install_hex.sh).
      hex: [
        ignore_advisories: [
          "EEF-CVE-2026-43966",
          "EEF-CVE-2026-43969",
          # Published 2026-08-18; still unpatched on Hex cowlib 2.19.0.
          "EEF-CVE-2026-43971"
        ]
      ],
      test_coverage: [
        tool: ExCoveralls,
        ignore_modules: [
          Mix.Tasks.CheckQuickbooksSync,
          Mix.Tasks.Ci.EmailPreviews,
          Mix.Tasks.Ci.QueryExplain,
          Mix.Tasks.CopyVendorAssets,
          Mix.Tasks.DebugEmails,
          Mix.Tasks.ExpireCheckoutSessions,
          Mix.Tasks.GenerateVideoPosters,
          Mix.Tasks.LintNotificationSamples,
          Mix.Tasks.Message.Requeue,
          Mix.Tasks.Quickbooks.RetrySyncs,
          Mix.Tasks.Quickbooks.VerifySandbox,
          Mix.Tasks.ShellLint,
          Mix.Tasks.StripStaticImageMetadata,
          Mix.Tasks.TestOutageEmail,
          Mix.Tasks.TestSubscriptionExpiration,
          Mix.Tasks.Webhook.Reprocess,
          Ysc.Application,
          Ysc.Alerts.DiscordHttpClient,
          Ysc.Ci.QueryExplain,
          Ysc.Cldr,
          Ysc.Cldr.Currency,
          Ysc.Cldr.DateTime.Format,
          Ysc.Cldr.DateTime.Formatter,
          Ysc.Cldr.List,
          Ysc.Cldr.Unit,
          Ysc.Credo.NoExternalUrlsInTestConfig,
          Ysc.Credo.NoSleepInTests,
          Ysc.Credo.DateFieldSchemaTypes,
          Ysc.Credo.DateFieldConversions,
          Ysc.Customers.Behaviour,
          Ysc.Flowroute.Client,
          Ysc.Payments.Behaviour,
          Ysc.PromEx,
          Ysc.PropertyOutages.Scraper,
          Ysc.PropertyOutages.Scheduler,
          Ysc.PropertyOutages.OutageScraperWorker,
          Ysc.Quickbooks.Client,
          Ysc.Quickbooks.ClientBehaviour,
          Ysc.SNS.SignatureVerifier,
          Ysc.Stripe.InvoiceBehaviour,
          Ysc.Stripe.PaymentIntentBehaviour,
          Ysc.Stripe.PaymentMethodBehaviour,
          Ysc.Stripe.RetryHelper,
          Ysc.Stripe.SetupIntentBehaviour,
          Ysc.StripeBehaviour,
          Ysc.StripeClient,
          YscWeb.AdminMoneyLive,
          YscWeb.AdminMediaLive,
          YscWeb.AdminSettingsLive,
          YscWeb.AdminUserDetailsLive,
          YscWeb.AdminMembershipsLive,
          YscWeb.AdminBookingsLive,
          YscWeb.AdminEventsNewLive,
          YscWeb.AdminNewsletterEditorLive,
          YscWeb.AdminPostEditorLive,
          YscWeb.DevButtonShowcaseLive,
          YscWeb.DevAvatarShowcaseLive,
          Ysc.Stripe.WebhookHandler,
          Ysc.Quickbooks.Sync,
          Ysc.ExpenseReports.QuickbooksSync,
          YscWeb.Workers.ImageProcessor,
          YscWeb.Workers.ImageReprocessor,
          YscWeb.Workers.QuickbooksSyncExpenseReportBackupWorker,
          YscWeb.Workers.QuickbooksSyncExpenseReportWorker,
          YscWeb.Workers.CreateStripeCustomerWorker,
          YscWeb.Telemetry,
          YscWeb.Uploads,
          YscWeb.EventDetailsLive,
          YscWeb.TahoeBookingLive,
          YscWeb.ExpenseReportLive,
          YscWeb.BookingCheckoutLive,
          YscWeb.CoreComponents,
          YscWeb.Components.AvailabilityCalendar,
          YscWeb.AdminEventsLive.TicketTierForm,
          YscWeb.AdminEventsLive.TicketTierManagement,
          LivePhone,
          YscWeb.Components.Autocomplete,
          YscWeb.MediaPickerComponent,
          YscWeb.UploadComponent,
          YscWeb.AgendaEditComponent,
          YscWeb.AgendasLive.FormComponent,
          YscWeb.AdminEventsLive.ScheduleEventForm,
          YscWeb.AdminEventsLive.TicketReservationForm,
          YscWeb.TrixUploadsController,
          Ysc.Tickets.StripeService,
          YscWeb.AdminNewslettersLive,
          YscWeb.AdminUsersLive,
          YscWeb.AdminEventsLive,
          YscWeb.AdminPostsLive,
          YscWeb.AdminDashboardLive,
          YscWeb.BookingReceiptLive,
          YscWeb.AccountSetupLive,
          YscWeb.OrderConfirmationLive,
          YscWeb.UserTicketsLive,
          YscWeb.UserLoginLive,
          Ysc.Subscriptions,
          Ysc.Tickets,
          Ysc.Media,
          Ysc.Customers,
          YscWeb.HomeLive,
          YscWeb.PasskeyRegistrationLive,
          YscWeb.PaymentSuccessLive,
          Ysc.Controllers.StripePaymentMethodController,
          YscWeb.Workers.QuickbooksSyncRetryWorker,
          YscWeb.Workers.QuickbooksSyncRefundWorker,
          YscWeb.Workers.QuickbooksSyncPayoutWorker,
          Ysc.Stripe.WebhookReconciliationWorker
        ]
      ]
    ]
  end

  def cli, do: []

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Ysc.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon, :tzdata]
    ]
  end

  # Gradual typing in tests produces many warnings on intentional invalid-arg assert_raise calls.
  defp elixirc_options_for(:test), do: []
  defp elixirc_options_for(_), do: [module_definition: :interpreted]

  # Specifies which paths to compile per environment.
  # dev/ contains custom Credo checks (Credo is only a dev/test dep), so we must not compile it in prod.
  defp elixirc_paths(:test), do: ["lib", "test/support", "dev"]
  defp elixirc_paths(:dev), do: ["lib", "dev"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      # GHSA-rhv4-8758-jx7v: Decimal < 3.0.0 (DoS via unbounded exponent). Override pulls 3.1.x onto
      # transitive ~> 2.x (e.g. retry_on).
      {:decimal, "~> 3.1", override: true},
      # ex_aws 2.7+ and stripity_stripe 3.3+ require hackney 4.x; tzdata still lists ~> 1.17
      # and its Hackney adapter expects the 1.x body/ref API. See Ysc.Tzdata.HttpClient.
      # webtransport 0.4.3 pins h2 ~> 0.10.4; hackney 4.7+ needs h2 ~> 0.11.0 — override below.
      {:hackney, "~> 4.7", override: true},
      {:h2, "~> 0.11.0", override: true},
      # ex_cldr_calendars 2.4.4 pins digital_token ~> 1.0; ex_cldr_numbers allows 1.x or 2.x but
      # otherwise resolves to 2.0, which blocks the calendars upgrade.
      {:digital_token, "~> 1.0", override: true},
      {:argon2_elixir, "~> 4.1"},
      {:atomex, "~> 0.5"},
      # EEF-CVE-2026-47079/47080/48590: entity-like sequences, CDATA ]]> breakout,
      # and invalid element/attribute names; fixed in xml_builder 2.4.1+. atomex
      # still lists ~> 2.1, so pin the patched floor (used for Atom feeds).
      {:xml_builder, "~> 2.4.1", override: true},
      # Vendored to fix a Range.new/2 deprecation warning upstream hasn't
      # released a fix for — see vendor/blurhash/README.md.
      {:blurhash, path: "vendor/blurhash"},
      {:brotli, ">= 0.0.0", runtime: false},
      {:cachex, "~> 4.1"},
      {:chromic_pdf, "~> 1.17"},
      {:cloak_ecto, "~> 1.3"},
      # Official Hex cowlib 2.19.0 (cowboy 2.18 needs >= 2.19; fixes EEF-CVE-2026-59248).
      # EEF-CVE-2026-43969/43966/43971: still unpatched — ignored until 2026-10-04
      # (see mix.exs hex config).
      {:cowboy, "~> 2.18", override: true},
      {:cowlib, "~> 2.19", override: true},
      {:credo, "~> 1.7.19", only: [:dev, :test], runtime: false},
      {:csv, "~> 3.2"},
      {:debouncer, "~> 1.0"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:dns_cluster, "~> 0.2"},
      {:ecto_enum, "~> 1.4"},
      {:ecto_psql_extras, "~> 0.8"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_ulid, "~> 0.3"},
      {:eqrcode, "~> 0.2"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:ex_aws_s3, "~> 2.5"},
      {:ex_aws, "~> 2.7"},
      {:ex_cldr_calendars, "~> 2.4"},
      {:ex_cldr_currencies, "~> 2.17"},
      {:ex_cldr_dates_times, "~> 2.25"},
      {:ex_cldr_numbers, "~> 2.38"},
      {:ex_cldr_person_names, "~> 1.1"},
      {:ex_cldr_territories, "~> 2.12"},
      {:ex_cldr_units, "~> 3.20"},
      {:ex_cldr, "~> 2.47"},
      {:ex_money_sql, "~> 1.12"},
      {:ex_phone_number, "~> 0.4"},
      {:excoveralls, "~> 0.18", only: :test, runtime: false},
      {:file_type, "~> 0.1.0"},
      {:finch, "~> 0.21"},
      # 1.10.0: EEF-CVE-2026-82728 (unbounded HTTP/1 status-line / chunk-extension
      # buffering) and EEF-CVE-2026-82729 (quadratic chunk-size parsing). Finch
      # still lists mint ~> 1.8, so pin the patched floor.
      {:mint, "~> 1.10", override: true},
      {:floki, "~> 0.38"},
      {:flop, "~> 0.28.0"},
      {:flop_phoenix, "~> 0.26.3"},
      {:gen_smtp, "~> 1.3"},
      {:gettext, "~> 0.26"},
      {:goth, "~> 1.4"},
      # 7.4.1: TokenBucket ETS refill uses milliseconds instead of whole
      # seconds. We use default :fix_window (hit/3 scale+limit), not
      # TokenBucket, so the patch is unused; pin the patched floor.
      {:hammer, "~> 7.4.1"},
      # 1.5.5: CSS.scrub treats nested tags inside <style> as empty (parser can
      # pass a tree instead of a string); HTML5 also tightens meta http-equiv
      # and object data=. We use BasicHTML / TrixScrubber / strip_tags, not
      # HTML5, but pin the patched floor.
      {:html_sanitize_ex, "~> 1.5.5"},
      {:image, "~> 0.72"},
      {:iso, "~> 1.4"},
      {:jason, "~> 1.4"},
      # Pin exact version: jose is pulled by joken (~> 1.11.10) and goth (~> 1.11).
      {:jose, "1.11.12", override: true},
      {:joken, "~> 2.6"},
      # 3.0.3: require spek ~> 0.5.0 (associativity flattening in Spek.optimize/1).
      # DSL and authorize/4 return values are unchanged.
      {:let_me, "~> 3.0"},
      {:live_toast, "~> 0.9"},
      {:locus, "~> 2.3"},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      # passbook pins nested_filter ~> 1.2.2; 2.x keeps drop_by_key/drop_by_value API used in Passbook.Pass.generate_json/1.
      {:nested_filter, "~> 2.1", override: true},
      {:mjml_eex, "~> 0.13"},
      {:mox, "~> 1.2", only: :test},
      # 2.24.1: ack only while the job is still executing (prevents a later
      # execution from overwriting completed/snoozed); notifier listeners live
      # in Oban.Notifier.Registry; notify/3 returns {:error, _} instead of
      # exiting. AdminSettingsLive still uses Oban.Notifier.listen/1 (:ok).
      # dispatch_cooldown is now a valid start_queue option (unused).
      {:oban, "~> 2.24.1"},
      {:passbook, "~> 0.1"},
      {:phoenix_bakery, "~> 1.0", runtime: false},
      {:phoenix_ecto, "~> 4.7"},
      {:phoenix_html_helpers, "~> 1.0"},
      {:phoenix_html, "~> 4.3"},
      # 0.9.1: skip Ecto repos that cannot resolve an extras module
      # (dynamic/unnamed names from Ecto.Repo.all_running/0). We only
      # have named Ysc.Repo + ecto_psql_extras; pin the patched floor.
      {:phoenix_live_dashboard, "~> 0.9.1"},
      {:phoenix_live_reload, "~> 1.7", only: :dev},
      # 1.2.11: discard stale diffs if a view rejoins before the first join
      # succeeds; cancel LiveComponent asyncs on removal; HTMLFormatter
      # skips EEx→curly migrations that would close interpolation early.
      {:phoenix_live_view, "~> 1.2.11"},
      {:phoenix_test, "~> 0.12", only: :test, runtime: false},
      {:phoenix_turnstile, "~> 1.2"},
      # EEF-CVE-2026-56811/56812: channel join DoS + Presence JS prototype collision; fixed in 1.8.9+.
      # 1.8.12: clear return_to after login; drop channel messages without a join_ref.
      # 1.8.13: phoenix.js reconnects after Chrome freeze/resume when visibilitychange is skipped.
      {:phoenix, "~> 1.8.13"},
      # plug 1.20.0/1.20.1 retired on Hex (accidental Plug.Conn.upgrade break); pin 1.20.2+.
      {:plug, "~> 1.20.2", override: true},
      {:plug_cowboy, "~> 2.9"},
      {:postgrex, "~> 0.22"},
      {:prom_ex, "~> 1.12"},
      {:remote_ip, "~> 1.2"},
      {:req, "~> 0.7"},
      {:retry_on, "~> 0.1"},
      # 13.5.0: optional Oban cron should_report_error_check_in_callback; tracing
      # span/parent fixes. We do not enable Sentry.Integrations.Oban or OpenTelemetry.
      # 13.5.1: rate-limit windows log once; per-event 429 drops at :debug (SDK spec).
      {:sentry, "~> 13.5.1"},
      {:sobelow, "~> 0.15", only: [:dev, :test], runtime: false},
      {:stripity_stripe, "~> 3.3"},
      # EEF-CVE-2026-54893: Microsoft Graph adapter URL path injection; fixed in 1.26.3+.
      # 1.27.1: AmazonSES returns {:error, %{code, message}} instead of crashing when
      # SES error XML is missing Code/Message nodes (we use SES).
      {:swoosh, "~> 1.27.1"},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      # 1.2.0: tags may be a 1-arity function (supersedes tag_values in docs).
      # tag_values is still supported and emits no deprecation warning. We keep
      # tag_values because PromEx/Peep, LiveDashboard, and prometheus_core still
      # read metric.tags as a list of keys plus metric.tag_values/1.
      {:telemetry_metrics, "~> 1.2"},
      {:telemetry_poller, "~> 1.3"},
      {:timex, "~> 3.7"},
      {:ueberauth_facebook, "~> 0.10"},
      {:ueberauth_google, "~> 0.10"},
      {:ueberauth, "~> 0.10"},
      {:uuid, "~> 1.1"},
      {:wax_, "~> 0.7"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      precommit: [
        "format",
        "compile --warnings-as-errors",
        "credo --strict",
        "dialyzer",
        "shell_lint",
        "lint_notification_samples"
      ],
      test: [
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "run priv/repo/test_seeds.exs",
        "test"
      ],
      "assets.setup": [
        "tailwind.install --if-missing",
        "esbuild.install --if-missing"
      ],
      "assets.build": [
        "copy_vendor_assets",
        "generate_video_posters",
        "strip_static_image_metadata",
        "tailwind default",
        "tailwind admin",
        "esbuild default",
        "esbuild admin",
        "esbuild html5_qrcode"
      ],
      "assets.deploy": [
        "copy_vendor_assets",
        "generate_video_posters",
        "strip_static_image_metadata",
        "tailwind default --minify",
        "tailwind admin --minify",
        "esbuild default --minify",
        "esbuild admin --minify",
        "esbuild html5_qrcode",
        "phx.digest"
      ]
    ]
  end
end
