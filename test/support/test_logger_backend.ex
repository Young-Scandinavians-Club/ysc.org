defmodule Ysc.TestLoggerBackend do
  @moduledoc """
  Custom logger backend for tests that filters out expected test errors.
  This reduces log noise from expected error scenarios during test runs.
  """

  @behaviour GenEvent

  # Patterns that indicate expected test errors (these are tested scenarios)
  @expected_error_patterns [
    "DBConnection.ConnectionError",
    "Postgrex.Protocol",
    # QuickBooks validation errors (tests deliberately trigger these)
    "[QB] create_purchase_sales_receipt: CRITICAL",
    # QuickBooks Client token refresh (tests call Client without valid config)
    "Failed to refresh QuickBooks access token",
    # Stripe webhook duplicate/race (tests exercise duplicate event handling)
    "Webhook event not found after duplicate error - race condition",
    "evt_not_found_after_dup",
    # Webhook retry worker (tests exercise unsupported provider / parse failure path)
    "Failed to parse webhook event",
    "unsupported_provider",
    # Webhook reconciliation worker (tests exercise failure path e.g. api_connection_error)
    "Webhook reconciliation failed",
    # Payment success LiveView (tests exercise booking_not_found / redirect failure path)
    "Failed to redirect from payment success after retries",
    # Ledgers process_payment (tests exercise payment_exists_but_not_completed path)
    "Failed to process payment in ledger"
  ]

  def init(_) do
    {:ok, %{}}
  end

  # MFAs that log expected test errors (suppress any error from these in tests)
  @suppress_error_mfas [
    {Ysc.Stripe.WebhookReconciliationWorker, :perform, 1},
    {YscWeb.Workers.WebhookRetryWorker, :retry_webhook, 1},
    {Ysc.Stripe.WebhookHandler, :process_webhook, 1},
    {YscWeb.PaymentSuccessLive, :mount, 3},
    {Ysc.Ledgers, :process_payment, 1}
  ]

  def handle_event({level, _gl, {Logger, msg, _ts, md}}, state)
      when level == :error do
    # Suppress all db_connection errors - they're expected during test cleanup
    if md[:application] == :db_connection or
         md[:mfa] == {DBConnection.Connection, :handle_event, 4} do
      {:ok, state}
    else
      message_str = to_string(msg)
      # Also check metadata for error messages
      metadata_str = inspect(md)
      full_message = message_str <> " " <> metadata_str

      # Suppress any error from these MFAs (expected test-triggered paths)
      from_suppress_mfa? = md[:mfa] in @suppress_error_mfas

      # Check if this is an expected test error - if so, completely suppress it
      is_expected_error =
        from_suppress_mfa? or
          Enum.any?(@expected_error_patterns, fn pattern ->
            String.contains?(message_str, pattern) ||
              String.contains?(full_message, pattern)
          end) or String.contains?(message_str, "exited") or
          String.contains?(full_message, "exited")

      # Only log if it's not an expected test error
      unless is_expected_error do
        # Use minimal format for unexpected errors
        IO.puts(:stderr, "\n[ERROR] #{message_str}\n")
      end

      {:ok, state}
    end
  end

  def handle_event({_level, _gl, {Logger, _msg, _ts, _md}}, state) do
    # Don't log non-error messages (they should be filtered by level anyway)
    {:ok, state}
  end

  def handle_event(_, state) do
    {:ok, state}
  end

  def handle_call({:configure, _opts}, state) do
    {:ok, :ok, state}
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  def terminate(_reason, _state) do
    :ok
  end
end
