defmodule YscWeb.Workers.QuickbooksSyncPayoutWorkerTest do
  use Ysc.DataCase, async: false

  import Mox
  import Ysc.AccountsFixtures

  alias YscWeb.Workers.QuickbooksSyncPayoutWorker
  alias Ysc.Ledgers
  alias Ysc.Ledgers.{Payment, Payout}
  alias Ysc.Repo

  setup :verify_on_exit!

  setup do
    Ledgers.ensure_basic_accounts()
    Cachex.clear(:ysc_cache)

    Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

    Application.put_env(:ysc, :quickbooks,
      client_id: "test_client_id",
      client_secret: "test_client_secret",
      company_id: "test_company_id",
      access_token: "test_access_token",
      refresh_token: "test_refresh_token",
      bank_account_id: "bank_123",
      stripe_account_id: "stripe_account_123"
    )

    user = user_fixture()
    %{user: user}
  end

  describe "perform/1" do
    test "returns discard when payout not found" do
      job = %Oban.Job{
        id: 1,
        args: %{"payout_id" => Ecto.ULID.generate()},
        worker: "YscWeb.Workers.QuickbooksSyncPayoutWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      assert {:discard, :payout_not_found} =
               QuickbooksSyncPayoutWorker.perform(job)
    end

    test "returns ok when payout already synced", %{user: user} do
      stub(Ysc.Quickbooks.ClientMock, :query_account_by_name, fn _ ->
        {:ok, "acc_123"}
      end)

      stub(Ysc.Quickbooks.ClientMock, :query_class_by_name, fn _ ->
        {:ok, "class_123"}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _ ->
        {:ok, %{"Id" => "cust_1"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _, _opts ->
        {:ok, %{"Id" => "sr_1", "TotalAmt" => "100.00"}}
      end)

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :event,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_payout_synced",
          stripe_fee: Money.new(320, :USD),
          description: "Payment",
          property: nil,
          payment_method_id: nil
        })

      payment =
        payment
        |> Payment.changeset(%{
          quickbooks_sync_status: "synced",
          quickbooks_sales_receipt_id: "sr_1"
        })
        |> Repo.update!()
        |> Repo.reload!()

      {:ok, {_payout_payment, _tx, _entries, payout}} =
        Ledgers.process_stripe_payout(%{
          payout_amount: Money.new(10_000, :USD),
          stripe_payout_id: "po_synced",
          description: "Payout",
          currency: "usd",
          status: "paid",
          arrival_date: DateTime.utc_now(),
          metadata: %{}
        })

      {:ok, payout} = Ledgers.link_payment_to_payout(payout, payment)

      payout =
        payout
        |> Payout.changeset(%{
          quickbooks_sync_status: "synced",
          quickbooks_deposit_id: "dep_123",
          quickbooks_synced_at: DateTime.utc_now()
        })
        |> Repo.update!()
        |> Repo.reload!()

      # Sync.sync_payout/1 always checks an already-deposited payout against
      # QuickBooks for drift now (a payment can link after the deposit was
      # created); here the deposit already reflects the only linked payment,
      # so it should come back a no-op with no write. expect/3 (not stub/3)
      # so the test fails if that read is ever skipped, and deny/3
      # create_deposit so it fails if the code ever re-creates instead.
      expect(Ysc.Quickbooks.ClientMock, :get_deposit_by_id, fn "dep_123" ->
        {:ok,
         %{
           "Id" => "dep_123",
           "SyncToken" => "0",
           "Line" => [
             %{
               "Amount" => 100.00,
               "DetailType" => "DepositLineDetail",
               "LinkedTxn" => [
                 %{"TxnId" => "sr_1", "TxnType" => "SalesReceipt"}
               ]
             }
           ]
         }}
      end)

      deny(Ysc.Quickbooks.ClientMock, :create_deposit, 2)

      job = %Oban.Job{
        id: 1,
        args: %{"payout_id" => payout.id},
        worker: "YscWeb.Workers.QuickbooksSyncPayoutWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      assert :ok = QuickbooksSyncPayoutWorker.perform(job)

      reloaded = Repo.reload!(payout)
      assert reloaded.quickbooks_deposit_id == "dep_123"
    end

    test "returns ok when sync succeeds", %{user: user} do
      stub(Ysc.Quickbooks.ClientMock, :query_account_by_name, fn _ ->
        {:ok, "acc_123"}
      end)

      stub(Ysc.Quickbooks.ClientMock, :query_class_by_name, fn _ ->
        {:ok, "class_123"}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _ ->
        {:ok, %{"Id" => "cust_1"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _, _opts ->
        {:ok, %{"Id" => "sr_1", "TotalAmt" => "100.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _, _opts ->
        {:ok, %{"Id" => "dep_456", "TotalAmt" => "100.00"}}
      end)

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :event,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_payout_success",
          stripe_fee: Money.new(320, :USD),
          description: "Payment",
          property: nil,
          payment_method_id: nil
        })

      payment =
        payment
        |> Payment.changeset(%{
          quickbooks_sync_status: "synced",
          quickbooks_sales_receipt_id: "sr_1"
        })
        |> Repo.update!()
        |> Repo.reload!()

      {:ok, {_payout_payment, _tx, _entries, payout}} =
        Ledgers.process_stripe_payout(%{
          payout_amount: Money.new(10_000, :USD),
          stripe_payout_id: "po_success",
          description: "Payout",
          currency: "usd",
          status: "paid",
          arrival_date: DateTime.utc_now(),
          metadata: %{}
        })

      {:ok, payout} = Ledgers.link_payment_to_payout(payout, payment)
      payout = Repo.reload!(payout)

      job = %Oban.Job{
        id: 1,
        args: %{"payout_id" => payout.id},
        worker: "YscWeb.Workers.QuickbooksSyncPayoutWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      assert :ok = QuickbooksSyncPayoutWorker.perform(job)
      payout = Repo.reload!(payout)
      assert payout.quickbooks_sync_status == "synced"
      assert payout.quickbooks_deposit_id == "dep_456"
    end

    test "returns error when sync fails", %{user: user} do
      stub(Ysc.Quickbooks.ClientMock, :query_account_by_name, fn _ ->
        {:ok, "acc_123"}
      end)

      stub(Ysc.Quickbooks.ClientMock, :query_class_by_name, fn _ ->
        {:ok, "class_123"}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _ ->
        {:ok, %{"Id" => "cust_1"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _, _opts ->
        {:ok, %{"Id" => "sr_1", "TotalAmt" => "100.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _, _opts ->
        {:error, "QuickBooks API unavailable"}
      end)

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :event,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_payout_fail",
          stripe_fee: Money.new(320, :USD),
          description: "Payment",
          property: nil,
          payment_method_id: nil
        })

      payment =
        payment
        |> Payment.changeset(%{
          quickbooks_sync_status: "synced",
          quickbooks_sales_receipt_id: "sr_1"
        })
        |> Repo.update!()
        |> Repo.reload!()

      {:ok, {_payout_payment, _tx, _entries, payout}} =
        Ledgers.process_stripe_payout(%{
          payout_amount: Money.new(10_000, :USD),
          stripe_payout_id: "po_fail",
          description: "Payout",
          currency: "usd",
          status: "paid",
          arrival_date: DateTime.utc_now(),
          metadata: %{}
        })

      {:ok, payout} = Ledgers.link_payment_to_payout(payout, payment)
      payout = Repo.reload!(payout)

      job = %Oban.Job{
        id: 1,
        args: %{"payout_id" => payout.id},
        worker: "YscWeb.Workers.QuickbooksSyncPayoutWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      assert {:error, "QuickBooks API unavailable"} =
               QuickbooksSyncPayoutWorker.perform(job)
    end

    test "returns discard for a negative payout amount" do
      # Stripe sends payout.paid with a negative amount when it debits our
      # bank account to cover a negative Stripe balance - a QuickBooks
      # Deposit can't represent a withdrawal, so this must not retry.
      {:ok, {_payout_payment, _tx, _entries, payout}} =
        Ledgers.process_stripe_payout(%{
          payout_amount: Money.new(-68_145, :USD),
          stripe_payout_id: "po_negative",
          description: "Withdrawal to cover a negative balance",
          currency: "usd",
          status: "paid",
          arrival_date: DateTime.utc_now(),
          metadata: %{}
        })

      deny(Ysc.Quickbooks.ClientMock, :create_deposit, 2)

      job = %Oban.Job{
        id: 1,
        args: %{"payout_id" => payout.id},
        worker: "YscWeb.Workers.QuickbooksSyncPayoutWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      assert {:discard, :negative_payout_amount} =
               QuickbooksSyncPayoutWorker.perform(job)
    end
  end
end
