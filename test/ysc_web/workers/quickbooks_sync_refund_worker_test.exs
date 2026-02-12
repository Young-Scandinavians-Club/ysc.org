defmodule YscWeb.Workers.QuickbooksSyncRefundWorkerTest do
  use Ysc.DataCase, async: false

  import Mox
  import Ysc.AccountsFixtures

  alias YscWeb.Workers.QuickbooksSyncRefundWorker
  alias Ysc.Ledgers
  alias Ysc.Ledgers.Refund
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
      refresh_token: "test_refresh_token"
    )

    user = user_fixture()
    %{user: user}
  end

  describe "perform/1" do
    test "returns discard when refund not found" do
      job = %Oban.Job{
        id: 1,
        args: %{"refund_id" => Ecto.ULID.generate()},
        worker: "YscWeb.Workers.QuickbooksSyncRefundWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      assert {:discard, :refund_not_found} =
               QuickbooksSyncRefundWorker.perform(job)
    end

    test "returns ok when refund already synced", %{user: user} do
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
          external_payment_id: "pi_refund_synced",
          stripe_fee: Money.new(320, :USD),
          description: "Payment",
          property: nil,
          payment_method_id: nil
        })

      {:ok, {refund, _, _}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(2_000, :USD),
          external_refund_id: "re_synced",
          reason: "Refund"
        })

      refund =
        refund
        |> Refund.changeset(%{
          quickbooks_sync_status: "synced",
          quickbooks_sales_receipt_id: "sr_refund_123"
        })
        |> Repo.update!()
        |> Repo.reload!()

      job = %Oban.Job{
        id: 1,
        args: %{"refund_id" => refund.id},
        worker: "YscWeb.Workers.QuickbooksSyncRefundWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      assert :ok = QuickbooksSyncRefundWorker.perform(job)
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

      stub(Ysc.Quickbooks.ClientMock, :get_or_create_item, fn _name, _opts ->
        {:ok, "item_event_123"}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_refund_receipt, fn _, _opts ->
        {:ok, %{"Id" => "rr_1", "TotalAmt" => "20.00"}}
      end)

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :event,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_refund_success",
          stripe_fee: Money.new(320, :USD),
          description: "Payment",
          property: nil,
          payment_method_id: nil
        })

      payment =
        payment
        |> Ecto.Changeset.change(
          quickbooks_sync_status: "synced",
          quickbooks_sales_receipt_id: "sr_1"
        )
        |> Repo.update!()
        |> Repo.reload!()

      {:ok, {refund, _, _}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(2_000, :USD),
          external_refund_id: "re_success",
          reason: "Refund"
        })

      Process.sleep(100)
      refund = Repo.reload!(refund)

      refund =
        if refund.quickbooks_sync_status == "synced" do
          refund
          |> Refund.changeset(%{
            quickbooks_sync_status: "pending",
            quickbooks_sales_receipt_id: nil,
            quickbooks_response: nil
          })
          |> Repo.update!()
          |> Repo.reload!()
        else
          refund
        end

      job = %Oban.Job{
        id: 1,
        args: %{"refund_id" => refund.id},
        worker: "YscWeb.Workers.QuickbooksSyncRefundWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      assert :ok = QuickbooksSyncRefundWorker.perform(job)
      refund = Repo.reload!(refund)
      assert refund.quickbooks_sync_status == "synced"
      assert refund.quickbooks_sales_receipt_id == "rr_1"
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

      stub(Ysc.Quickbooks.ClientMock, :get_or_create_item, fn _name, _opts ->
        {:ok, "item_event_123"}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_refund_receipt, fn _, _opts ->
        {:error, "Rate limited"}
      end)

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :event,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_refund_fail",
          stripe_fee: Money.new(320, :USD),
          description: "Payment",
          property: nil,
          payment_method_id: nil
        })

      payment =
        payment
        |> Ecto.Changeset.change(
          quickbooks_sync_status: "synced",
          quickbooks_sales_receipt_id: "sr_1"
        )
        |> Repo.update!()
        |> Repo.reload!()

      {:ok, {refund, _, _}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(1_000, :USD),
          external_refund_id: "re_fail",
          reason: "Refund"
        })

      Process.sleep(100)
      refund = Repo.reload!(refund)

      refund =
        if refund.quickbooks_sync_status == "synced" do
          refund
          |> Refund.changeset(%{
            quickbooks_sync_status: "pending",
            quickbooks_sales_receipt_id: nil
          })
          |> Repo.update!()
          |> Repo.reload!()
        else
          refund
        end

      job = %Oban.Job{
        id: 1,
        args: %{"refund_id" => refund.id},
        worker: "YscWeb.Workers.QuickbooksSyncRefundWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      assert {:error, "Rate limited"} = QuickbooksSyncRefundWorker.perform(job)
    end
  end
end
