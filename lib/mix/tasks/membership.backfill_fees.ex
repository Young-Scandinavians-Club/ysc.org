defmodule Mix.Tasks.Membership.BackfillFees do
  @moduledoc """
  Mix task for backfilling missing Stripe processing fee ledger entries on
  membership/subscription payments (see `Ysc.Webhooks.MembershipFeeBackfill`
  for the root cause).

  ## Examples:

      # List payments missing a Stripe fee entry
      mix membership.backfill_fees list

      # Show what would be booked, without writing anything
      mix membership.backfill_fees run --dry-run

      # Book the missing fee entries
      mix membership.backfill_fees run

      # Limit how many payments are processed
      mix membership.backfill_fees run --limit 10 --dry-run
  """

  use Mix.Task
  require Ysc.Logging

  alias Ysc.Webhooks.MembershipFeeBackfill

  @shortdoc "Backfill missing Stripe fee ledger entries on membership payments"

  def run(args) do
    Mix.Task.run("app.start")

    case args do
      ["list" | opts] ->
        list_affected(opts)

      ["run" | opts] ->
        run_backfill(opts)

      _ ->
        show_help()
    end
  end

  defp list_affected(opts) do
    opts = parse_opts(opts)
    payments = MembershipFeeBackfill.list_affected_payments(opts)

    if Enum.empty?(payments) do
      Ysc.Logging.info("No payments found missing a Stripe fee entry.")
    else
      Ysc.Logging.info(
        "Found #{length(payments)} payments missing a Stripe fee entry:"
      )

      Ysc.Logging.info("")

      Enum.each(payments, fn payment ->
        Ysc.Logging.info("Payment ID: #{payment.id}")
        Ysc.Logging.info("  Reference: #{payment.reference_id}")
        Ysc.Logging.info("  Invoice: #{payment.external_payment_id}")
        Ysc.Logging.info("  Amount: #{Money.to_string!(payment.amount)}")
        Ysc.Logging.info("  Payment Date: #{payment.payment_date}")
        Ysc.Logging.info("")
      end)
    end
  end

  defp run_backfill(opts) do
    opts = parse_opts(opts)

    if opts[:dry_run] do
      Ysc.Logging.info("🔍 Dry run - showing what would be processed...")
    else
      Ysc.Logging.info("Backfilling missing membership payment Stripe fees...")
    end

    result = MembershipFeeBackfill.run(opts)

    Ysc.Logging.info("")
    Ysc.Logging.info("Summary: #{result.summary}")
    Ysc.Logging.info("Total Found: #{result.total_found}")

    if not opts[:dry_run] do
      Ysc.Logging.info("Booked: #{result.booked}")
      Ysc.Logging.info("No Fee: #{result.no_fee}")
      Ysc.Logging.info("Already Booked: #{result.already_booked}")
      Ysc.Logging.info("Failed: #{result.failed}")

      if result.failed > 0 do
        Ysc.Logging.info("")
        Ysc.Logging.info("Failed payment details:")

        Enum.each(result.results, fn
          {payment, {:error, reason}} ->
            Ysc.Logging.error("  #{payment.id}: #{inspect(reason)}")

          _ ->
            :ok
        end)
      end
    end
  end

  defp parse_opts(opts) do
    opts
    |> Enum.chunk_every(2)
    |> Enum.reduce([], fn
      ["--limit", limit], acc ->
        Keyword.put(acc, :limit, String.to_integer(limit))

      ["--dry-run"], acc ->
        Keyword.put(acc, :dry_run, true)

      _, acc ->
        acc
    end)
  end

  defp show_help do
    Ysc.Logging.info("""
    Membership Payment Fee Backfill

    Usage:
      mix membership.backfill_fees <command> [options]

    Commands:
      list                    List payments missing a Stripe fee entry
      run                     Book the missing fee entries

    Options:
      --limit <number>        Limit number of payments (default: 1000)
      --dry-run               Show what would be processed without writing anything

    Examples:
      mix membership.backfill_fees list
      mix membership.backfill_fees run --dry-run
      mix membership.backfill_fees run --limit 10 --dry-run
      mix membership.backfill_fees run
    """)
  end
end
