defmodule Ysc.Ledgers.ReconciliationTelemetryTest do
  @moduledoc """
  Telemetry tests for reconciliation.

  Runs with async: false to avoid flakiness from parallel tests affecting
  reconciliation state (e.g. ledger balance or entity totals).
  """
  use Ysc.DataCase, async: false

  alias Ysc.Ledgers
  alias Ysc.Ledgers.Reconciliation

  import Ysc.AccountsFixtures

  setup do
    Ledgers.ensure_basic_accounts()

    Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

    Application.put_env(:ysc, :quickbooks,
      client_id: "test_client_id",
      client_secret: "test_client_secret",
      company_id: "test_company_id",
      access_token: "test_access_token",
      refresh_token: "test_refresh_token",
      event_item_id: "event_item_123",
      donation_item_id: "donation_item_123",
      bank_account_id: "bank_account_123",
      stripe_account_id: "stripe_account_123"
    )

    import Mox

    stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
      {:ok, %{"Id" => "qb_customer_default"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params, _opts ->
      {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
      {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
    end)

    user = user_fixture()

    %{user: user}
  end

  describe "telemetry and monitoring" do
    test "emits telemetry event on successful reconciliation", %{user: user} do
      test_pid = self()

      :telemetry.attach(
        "test-reconciliation-success",
        [:ysc, :ledgers, :reconciliation_completed],
        fn event_name, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event_name, measurements, metadata})
        end,
        nil
      )

      Ledgers.process_payment(%{
        user_id: user.id,
        amount: Money.new(10_000, :USD),
        external_provider: :stripe,
        external_payment_id: "pi_telemetry_success",
        payment_date: DateTime.truncate(DateTime.utc_now(), :second),
        entity_type: :membership,
        entity_id: Ecto.ULID.generate(),
        stripe_fee: Money.new(300, :USD),
        description: "Telemetry test",
        property: :general,
        payment_method_id: nil
      })

      {:ok, report} = Reconciliation.run_full_reconciliation()

      failing_checks =
        report.checks
        |> Enum.filter(fn {_k, v} -> v.status != :ok end)
        |> Enum.map_join(", ", fn {k, v} -> "#{k}=#{v.status}" end)

      assert report.overall_status == :ok,
             "Reconciliation must succeed. Failing checks: #{failing_checks}. " <>
               "Report: payments=#{report.checks.payments.status}, " <>
               "refunds=#{report.checks.refunds.status}, " <>
               "ledger_balance=#{report.checks.ledger_balance.status}, " <>
               "orphaned_entries=#{report.checks.orphaned_entries.status}, " <>
               "entity_totals=#{report.checks.entity_totals.status}."

      assert_receive {:telemetry_event,
                      [:ysc, :ledgers, :reconciliation_completed], measurements,
                      metadata},
                     1000

      assert is_integer(measurements.duration)
      assert measurements.duration > 0
      assert measurements.count == 1
      assert metadata.status == "success"
      assert metadata.has_errors == false

      :telemetry.detach("test-reconciliation-success")
    end
  end
end
