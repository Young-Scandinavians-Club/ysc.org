defmodule Ysc.MixProject do
  use Mix.Project

  def project do
    [
      app: :ysc,
      version: "1.0.16",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader],
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :credo, :stripity_stripe, :duckdbex],
        list_unused_filters: true
      ],
      test_coverage: [
        tool: ExCoveralls,
        ignore_modules: [
          Mix.Tasks.CheckQuickbooksSync,
          Mix.Tasks.CopyVendorAssets,
          Mix.Tasks.DebugEmails,
          Mix.Tasks.ExpireCheckoutSessions,
          Mix.Tasks.GenerateVideoPosters,
          Mix.Tasks.Message.Requeue,
          Mix.Tasks.Quickbooks.RetrySyncs,
          Mix.Tasks.Quickbooks.VerifySandbox,
          Mix.Tasks.ShellLint,
          Mix.Tasks.StripStaticImageMetadata,
          Mix.Tasks.TestOutageEmail,
          Mix.Tasks.TestSubscriptionExpiration,
          Mix.Tasks.Webhook.Reprocess,
          Mix.Tasks.Ysc.WpExtract,
          Mix.Tasks.Ysc.WpLoad,
          Mix.Tasks.Ysc.WpMigrationUnlock,
          Mix.Tasks.Ysc.WpSample,
          Mix.Tasks.Ysc.WpToDuckdb,
          Mix.Tasks.Ysc.WpValidate,
          Ysc.Application,
          Ysc.Alerts.DiscordHttpClient,
          Ysc.Cldr,
          Ysc.Cldr.Currency,
          Ysc.Cldr.DateTime.Format,
          Ysc.Cldr.DateTime.Formatter,
          Ysc.Cldr.List,
          Ysc.Cldr.Unit,
          Ysc.Credo.NoExternalUrlsInTestConfig,
          Ysc.Credo.NoSleepInTests,
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
          Ysc.WpMigration.Load,
          Ysc.WpMigration.Extract,
          Ysc.WpMigration.Validate,
          Ysc.WpMigration.SqlToDuckdb,
          Ysc.WpMigration.WpRepo,
          Ysc.WpMigration.HtmlTransformer,
          Ysc.WpMigration.PhpDeserialize,
          YscWeb.PostMigrationOnboardingLive,
          YscWeb.AdminMoneyLive,
          YscWeb.AdminMediaLive,
          YscWeb.AdminSettingsLive,
          YscWeb.AdminUserDetailsLive,
          YscWeb.AdminMembershipsLive,
          YscWeb.AdminBookingsLive,
          YscWeb.AdminEventsNewLive,
          YscWeb.AdminNewsletterEditorLive,
          YscWeb.AdminPostEditorLive,
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
          YscWeb.UserSettingsLive,
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
      {:argon2_elixir, "~> 4.1"},
      {:atomex, "~> 0.5"},
      {:blurhash, "~> 0.1", hex: :rinpatch_blurhash},
      {:brotli, ">= 0.0.0", runtime: false},
      {:cachex, "~> 4.1"},
      {:cloak_ecto, "~> 1.3"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:csv, "~> 3.2"},
      {:debouncer, "~> 1.0"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:dns_cluster, "~> 0.2"},
      {:duckdbex, "~> 0.3.21", only: [:dev], runtime: false},
      {:ecto_enum, "~> 1.4"},
      {:ecto_psql_extras, "~> 0.8"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_ulid, "~> 0.3"},
      {:eqrcode, "~> 0.2"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:ex_aws_s3, "~> 2.5"},
      {:ex_aws, "~> 2.6"},
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
      {:floki, "~> 0.38"},
      {:flop_phoenix, "~> 0.26"},
      {:gen_smtp, "~> 1.3"},
      {:gettext, "~> 0.26"},
      {:goth, "~> 1.4"},
      {:hammer, "~> 7.3"},
      {:html_sanitize_ex, "~> 1.5"},
      {:image, "~> 0.67"},
      {:iso, "~> 1.4"},
      {:jason, "~> 1.4"},
      {:joken, "~> 2.6"},
      {:let_me, "~> 1.2.3"},
      {:live_toast, "~> 0.8"},
      {:locus, "~> 2.3"},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:mjml_eex, "~> 0.13"},
      {:mogrify, "~> 0.8"},
      {:mox, "~> 1.2", only: :test},
      {:oban, "~> 2.22"},
      {:passbook, "~> 0.1"},
      {:phoenix_bakery, "~> 1.0", runtime: false},
      {:phoenix_ecto, "~> 4.7"},
      {:phoenix_html_helpers, "~> 1.0"},
      {:phoenix_html, "~> 4.3"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix_test, "~> 0.11", only: :test, runtime: false},
      {:phoenix_turnstile, "~> 1.2"},
      {:phoenix, "~> 1.8"},
      {:plug_cowboy, "~> 2.8"},
      {:postgrex, "~> 0.22"},
      {:prom_ex, "~> 1.11"},
      {:remote_ip, "~> 1.2"},
      {:req, "~> 0.5"},
      {:retry_on, "~> 0.1"},
      {:sentry, "~> 13.0"},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false},
      {:stripity_stripe, "~> 3.2"},
      {:swoosh, "~> 1.25"},
      {:tailwind, "~> 0.4", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.1"},
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
        "compile",
        "credo --strict",
        "dialyzer",
        "shell_lint"
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
