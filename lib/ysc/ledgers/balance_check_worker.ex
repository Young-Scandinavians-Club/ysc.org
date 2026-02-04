defmodule Ysc.Ledgers.BalanceCheckWorker do
  @moduledoc """
  Background worker for verifying ledger balance integrity.

  This worker runs daily at midnight UTC to:
  - Verify that the ledger is balanced (debits = credits)
  - Identify which accounts are imbalanced if there's an issue
  - Send alerts if imbalances are detected
  - Log detailed information for troubleshooting

  Scheduled to run: 0 0 * * * (midnight UTC daily)
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 3

  require Logger

  alias Ysc.Ledgers

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Starting daily ledger balance check")

    case Ledgers.get_ledger_imbalance_details() do
      {:ok, :balanced} ->
        Logger.info("Ledger balance check completed: BALANCED ✓")
        {:ok, :balanced}

      {:error, {:imbalanced, difference, imbalanced_accounts}} ->
        handle_imbalance(difference, imbalanced_accounts)
        {:error, :imbalanced}
    end
  end

  @doc """
  Manually trigger a ledger balance check.
  Useful for on-demand verification or debugging.
  """
  def check_balance_now do
    perform(%Oban.Job{})
  end

  # Handle ledger imbalance by sending alerts and logging details
  defp handle_imbalance(difference, imbalanced_accounts) do
    # Critical condition: report to Sentry instead of emitting error-level logs.
    Logger.warning("CRITICAL: Ledger imbalance detected during scheduled check",
      difference: Money.to_string!(difference),
      account_count: length(imbalanced_accounts),
      timestamp: DateTime.utc_now()
    )

    Sentry.capture_message("Ledger imbalance detected during scheduled check",
      level: :error,
      extra: %{
        difference: Money.to_string!(difference),
        account_count: length(imbalanced_accounts),
        timestamp: DateTime.utc_now()
      },
      tags: %{
        ledger: "scheduled_balance_check"
      }
    )

    # Group accounts by type for the alert
    accounts_by_type = group_accounts_by_type(imbalanced_accounts)

    # Send alert with detailed information
    send_imbalance_alert(%{
      difference: difference,
      total_accounts: length(imbalanced_accounts),
      accounts_by_type: accounts_by_type,
      imbalanced_accounts: imbalanced_accounts
    })

    # Log individual account details for investigation
    log_imbalanced_accounts(imbalanced_accounts)
  end

  # Group accounts by their type (asset, liability, revenue, expense)
  defp group_accounts_by_type(imbalanced_accounts) do
    Enum.group_by(imbalanced_accounts, fn {account, _balance} ->
      account.account_type
    end)
    |> Enum.map(fn {type, accounts} ->
      total_balance =
        Enum.reduce(accounts, Money.new(0, :USD), fn {_account, balance}, acc ->
          Money.add(acc, balance)
        end)

      {type, length(accounts), total_balance}
    end)
  end

  # Log details about each imbalanced account
  defp log_imbalanced_accounts(imbalanced_accounts) do
    Logger.warning("Imbalanced accounts breakdown:")

    Enum.each(imbalanced_accounts, fn {account, balance} ->
      Logger.warning(
        "  - #{account.name} (#{account.account_type}): #{Money.to_string!(balance)}"
      )
    end)
  end

  # Send alert to monitoring system
  defp send_imbalance_alert(details) do
    %{
      difference: difference,
      total_accounts: total_accounts,
      accounts_by_type: accounts_by_type,
      imbalanced_accounts: imbalanced_accounts
    } = details

    # Format account type summary
    type_summary =
      Enum.map_join(accounts_by_type, "\n", fn {type, count, total} ->
        "#{type}: #{count} accounts, total: #{Money.to_string!(total)}"
      end)

    # Format top 5 accounts by absolute value
    top_accounts =
      imbalanced_accounts
      |> Enum.sort_by(
        fn {_account, balance} ->
          abs(Money.to_decimal(balance))
        end,
        :desc
      )
      |> Enum.take(5)
      |> Enum.map_join("\n", fn {account, balance} ->
        "  #{account.name}: #{Money.to_string!(balance)}"
      end)

    alert_message = """
    🚨 CRITICAL: Ledger Imbalance Detected

    **Total Difference:** #{Money.to_string!(difference)}
    **Total Accounts Affected:** #{total_accounts}
    **Timestamp:** #{DateTime.utc_now() |> DateTime.to_iso8601()}

    **Breakdown by Account Type:**
    #{type_summary}

    **Top 5 Accounts by Value:**
    #{top_accounts}

    **Action Required:**
    1. Review recent transactions in the ledger
    2. Check for failed payment/refund processing
    3. Investigate any manual ledger entries
    4. Run: `Ysc.Ledgers.get_account_balances()` for full details

    **Investigation Commands:**
    ```elixir
    # Get full account breakdown
    Ysc.Ledgers.get_account_balances()

    # Check specific account
    Ysc.Ledgers.calculate_account_balance(account_id)

    # Get recent ledger entries
    Ysc.Ledgers.get_recent_payments(start_date, end_date)
    ```
    """

    Logger.error(alert_message)

    # NOTE: Integrate with your alerting system
    # Examples:
    # - send_slack_alert(alert_message)
    # - send_pagerduty_alert(alert_message)
    # - send_email_alert(alert_message)
    # - Sentry.capture_message(alert_message, level: :error)

    # For now, just ensure it's logged at ERROR level
    # which should be picked up by your log aggregation system
    :ok
  end

  @impl Oban.Worker
  def timeout(_job) do
    # Balance check should complete quickly, but allow 30 seconds for large datasets
    30_000
  end
end
