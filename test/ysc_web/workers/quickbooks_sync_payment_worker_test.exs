defmodule YscWeb.Workers.QuickbooksSyncPaymentWorkerTest do
  use Ysc.DataCase, async: false

  import Mox
  import Ysc.AccountsFixtures

  alias YscWeb.Workers.QuickbooksSyncPaymentWorker
  alias Ysc.Ledgers
  alias Ysc.Repo

  setup :verify_on_exit!

  setup do
    user = user_fixture()
    Ledgers.ensure_basic_accounts()

    Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

    Application.put_env(:ysc, :quickbooks,
      client_id: "test_client_id",
      client_secret: "test_client_secret",
      company_id: "test_company_id",
      access_token: "test_access_token",
      refresh_token: "test_refresh_token"
    )

    %{user: user}
  end

  describe "perform/1" do
    test "returns error when payment not found" do
      job = %Oban.Job{
        id: 1,
        args: %{"payment_id" => Ecto.ULID.generate()},
        worker: "YscWeb.Workers.QuickbooksSyncPaymentWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      assert {:discard, :payment_not_found} =
               QuickbooksSyncPaymentWorker.perform(job)
    end

    test "returns ok when payment already synced", %{user: user} do
      Ledgers.ensure_basic_accounts()

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :query_account_by_name, fn _name ->
        {:ok, "account_123"}
      end)

      stub(Ysc.Quickbooks.ClientMock, :query_class_by_name, fn _name ->
        {:ok, "class_123"}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_already_synced",
          stripe_fee: Money.new(320, :USD),
          description: "Test payment",
          property: nil,
          payment_method_id: nil
        })

      # Mark as already synced
      payment
      |> Ecto.Changeset.change(
        quickbooks_sync_status: "synced",
        quickbooks_sales_receipt_id: "sr_123"
      )
      |> Ysc.Repo.update!()

      job = %Oban.Job{
        id: 1,
        args: %{"payment_id" => payment.id},
        worker: "YscWeb.Workers.QuickbooksSyncPaymentWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      assert :ok = QuickbooksSyncPaymentWorker.perform(job)
    end

    test "returns error when sync fails", %{user: user} do
      Ledgers.ensure_basic_accounts()

      stub(Ysc.Quickbooks.ClientMock, :query_account_by_name, fn _ ->
        {:ok, "acc_123"}
      end)

      stub(Ysc.Quickbooks.ClientMock, :query_class_by_name, fn _ ->
        {:ok, "class_123"}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _ ->
        {:ok, %{"Id" => "qb_cust"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :get_or_create_item, fn _name, _opts ->
        {:ok, "item_123"}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _ ->
        {:error, "QuickBooks API error"}
      end)

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :event,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_sync_fail",
          stripe_fee: Money.new(320, :USD),
          description: "Payment",
          property: nil,
          payment_method_id: nil
        })

      payment = Repo.reload!(payment)

      payment =
        if payment.quickbooks_sync_status == "synced" do
          payment
          |> Ecto.Changeset.change(
            quickbooks_sync_status: "pending",
            quickbooks_sales_receipt_id: nil
          )
          |> Repo.update!()
          |> Repo.reload!()
        else
          payment
        end

      job = %Oban.Job{
        id: 1,
        args: %{"payment_id" => payment.id},
        worker: "YscWeb.Workers.QuickbooksSyncPaymentWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      assert {:error, "QuickBooks API error"} =
               QuickbooksSyncPaymentWorker.perform(job)
    end
  end
end
