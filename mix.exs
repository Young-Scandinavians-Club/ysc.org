defmodule Ysc.MixProject do
  use Mix.Project

  def project do
    [
      app: :ysc,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [
        tool: ExCoveralls,
        ignore_modules: [
          YscNative,
          YscWeb.PropertyCheckInLive.SwiftUI,
          YscWeb.TahoeCabinRulesLive.SwiftUI,
          YscWeb.TahoeStayingWithLive.SwiftUI,
          YscWeb.CoreComponents.SwiftUI,
          YscWeb.HomeLive.SwiftUI,
          YscWeb.Layouts.SwiftUI,
          YscWeb.Styles.App.SwiftUI,
          Ysc.Application,
          Ysc.Cldr,
          Ysc.Cldr.Currency,
          Ysc.Cldr.DateTime.Format,
          Ysc.Cldr.DateTime.Formatter,
          Ysc.Cldr.List,
          Ysc.Cldr.Unit,
          YscWeb.TahoeCabinRulesLive,
          YscWeb.TahoeStayingWithLive,
          YscWeb.PropertyCheckInLive,
          YscWeb.TestLogFilter,
          Mix.Tasks.CheckQuickbooksSync,
          Mix.Tasks.DebugEmails,
          Mix.Tasks.ExpireCheckoutSessions,
          Mix.Tasks.GenerateVideoPosters,
          Mix.Tasks.Message.Requeue,
          Mix.Tasks.TestOutageEmail,
          Mix.Tasks.TestSubscriptionExpiration,
          Mix.Tasks.Webhook.Reprocess
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
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:argon2_elixir, "~> 4.0"},
      {:blurhash, "~> 0.1.0", hex: :rinpatch_blurhash},
      {:brotli, ">= 0.0.0", runtime: false},
      {:cachex, "~> 3.6"},
      {:cloak_ecto, "~> 1.2"},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:csv, "~> 3.2"},
      {:debouncer, "~> 0.1"},
      {:dns_cluster, "~> 0.2"},
      {:ecto_enum, "~> 1.4"},
      {:ecto_psql_extras, "~> 0.6"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_ulid, "~> 0.3"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:excoveralls, "~> 0.18", only: :test, runtime: false},
      {:ex_aws_s3, "~> 2.0"},
      {:ex_aws, "~> 2.1"},
      {:ex_cldr_calendars, "~> 2.4"},
      {:ex_cldr_currencies, "~> 2.16"},
      {:ex_cldr_dates_times, "~> 2.25"},
      {:ex_cldr_numbers, "~> 2.36"},
      {:ex_cldr_person_names, "~> 1.1"},
      {:ex_cldr_territories, "~> 2.11"},
      {:ex_cldr_units, "~> 3.20"},
      {:ex_cldr, "~> 2.44"},
      {:ex_money_sql, "~> 1.0"},
      {:ex_phone_number, "~> 0.4"},
      {:file_type, "~> 0.1.0"},
      {:finch, "~> 0.17"},
      {:floki, ">= 0.30.0"},
      {:flop_phoenix, "~> 0.22.7"},
      {:gen_smtp, "~> 1.0"},
      {:gettext, "~> 0.24"},
      {:hammer, "~> 7.0"},
      {:hackney, "~> 1.9"},
      {:html_sanitize_ex, "~> 1.4"},
      {:image, "~> 0.37"},
      {:iso, ">= 0.0.0"},
      {:jason, "~> 1.4"},
      {:let_me, "~> 1.2.3"},
      {:live_view_native_live_form, "~> 0.3.1"},
      {:live_view_native_stylesheet, "~> 0.3.2"},
      {:live_view_native_swiftui, "~> 0.3.1"},
      {:live_view_native, "~> 0.3.1"},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:mjml_eex, "~> 0.12"},
      {:mogrify, "~> 0.8.0"},
      {:mox, "~> 1.0", only: :test},
      {:oban, "~> 2.17"},
      {:phoenix_bakery, "~> 0.1", runtime: false},
      {:phoenix_ecto, "~> 4.4"},
      {:phoenix_html_helpers, "~> 1.0"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:phoenix_live_view, "~> 0.20"},
      {:phoenix_test, "~> 0.5.2", only: :test, runtime: false},
      {:phoenix_turnstile, "~> 1.0"},
      {:phoenix, "~> 1.7"},
      {:plug_cowboy, "~> 2.6"},
      {:postgrex, "~> 0.20"},
      {:prom_ex, "~> 1.11"},
      {:remote_ip, "~> 1.2"},
      {:req, "~> 0.5"},
      {:retry_on, "~> 0.1.0"},
      {:sentry, "~> 11.0"},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false},
      {:stripity_stripe, "~> 2.17"},
      {:swoosh, "~> 1.14"},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.1"},
      {:telemetry_poller, "~> 1.3"},
      {:timex, "~> 3.7"},
      {:ueberauth_facebook, "~> 0.10"},
      {:ueberauth_google, "~> 0.10"},
      {:ueberauth, "~> 0.10"},
      {:uuid, "~> 1.1"},
      {:wax_, "~> 0.7.0"}
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
        "compile"
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
        "generate_video_posters",
        "tailwind default",
        "esbuild default"
      ],
      "assets.deploy": [
        "generate_video_posters",
        "tailwind default --minify",
        "esbuild default --minify",
        "phx.digest"
      ]
    ]
  end
end
