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
      {:phoenix, "~> 1.8.0"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      # 0.22.4: Escape comments on Postgrex.stream/4 (EEF-CVE-2026-66838).
      # We use Postgrex.query/start_link and AnalyticsRepo.query, not stream/4
      # or the :comment option. Public query APIs and BinaryExtension are
      # unchanged. Pin the patched floor.
      {:postgrex, "~> 0.22.4"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
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
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.3.0"},
      # 1.12.5: EEF-CVE-2026-74836 (HIGH) bounds/cancels HTTP/2 sends blocked on
      # the connection window; EEF-CVE-2026-75484 (MEDIUM) rejects HTTP/2 header
      # values with CR/LF/NUL. We use Bandit.PhoenixAdapter (bandit_pid/1 for
      # idle shutdown). Public adapter APIs are unchanged.
      {:bandit, "~> 1.12.5"},
      {:req, "~> 0.5"},
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
