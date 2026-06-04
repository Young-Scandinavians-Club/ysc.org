defmodule Ysc.Credo.NoExternalUrlsInTestConfig do
  use Credo.Check,
    id: "EX9002",
    base_priority: :high,
    category: :warning,
    param_defaults: [
      files: %{included: ["config/test.exs", "config/test.secret.exs"]},
      # Well-known external services whose URLs should never appear in test config.
      # Tests should use localhost or mocked adapters instead.
      blocked_hosts: [
        "discord.com",
        "discordapp.com",
        "stripe.com",
        "api.stripe.com",
        "sendgrid.com",
        "api.sendgrid.com",
        "slack.com",
        "hooks.slack.com",
        "twilio.com",
        "api.twilio.com",
        "amazonaws.com",
        "s3.amazonaws.com",
        "sentry.io",
        "o0.ingest.sentry.io",
        "intuit.com",
        "quickbooks.api.intuit.com"
      ]
    ],
    explanations: [
      check: """
      External service URLs should not appear in `config/test.exs`.

      When a real external URL is configured in the test environment, tests that
      exercise the configured client will make actual network requests. This
      causes several problems:

        * Tests become slow — DNS resolution, TLS handshakes, and round-trips to
          the real service can each add hundreds of milliseconds per test.
        * Tests become flaky — results depend on network availability and the
          remote service's uptime.
        * Tests may produce side-effects — a real Discord webhook may actually
          post messages; a real Stripe key may create real charges.

      ## Fixes

      **Option 1 – Disable the integration** (preferred for most services):

          # config/test.exs
          config :ysc, Ysc.Alerts.Discord,
            webhook_url: nil,
            enabled: false

      **Option 2 – Use a localhost URL for fast connection-refused errors**:

          # config/test.exs  — fails instantly, no network I/O
          config :ysc, Ysc.Alerts.Discord,
            webhook_url: "http://localhost:1",
            enabled: true

      **Option 3 – Mock the HTTP adapter** using Mox or Bypass so no real
      network call is ever attempted.

      The blocked hosts include: discord.com, stripe.com, sendgrid.com, slack.com,
      twilio.com, amazonaws.com, sentry.io, intuit.com, and more.
      """
    ]

  @impl Credo.Check
  def scheduled_in_group, do: 1

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    blocked_hosts = Params.get(params, :blocked_hosts, param_defaults()[:blocked_hosts])

    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, issue_meta, blocked_hosts))
    |> Enum.reverse()
  end

  # Match string literals and check whether they contain a blocked hostname.
  defp traverse({string, meta, nil} = ast, issues, issue_meta, blocked_hosts)
       when is_binary(string) do
    case find_blocked_host(string, blocked_hosts) do
      nil ->
        {ast, issues}

      host ->
        issue =
          format_issue(issue_meta,
            message:
              "External URL referencing \"#{host}\" found in test config. " <>
                "Use `enabled: false`, `http://localhost:1`, or a mock adapter instead. " <>
                "See `mix credo explain #{id()}` for alternatives.",
            trigger: string,
            line_no: meta[:line]
          )

        {ast, [issue | issues]}
    end
  end

  defp traverse(ast, issues, _issue_meta, _blocked_hosts), do: {ast, issues}

  defp find_blocked_host(string, blocked_hosts) do
    Enum.find(blocked_hosts, fn host ->
      String.contains?(string, host)
    end)
  end
end
