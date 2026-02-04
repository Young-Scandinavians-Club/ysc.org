defmodule YscWeb.Workers.QuickbooksSyncPayoutWorkerTest do
  use Ysc.DataCase, async: false

  import Mox

  alias YscWeb.Workers.QuickbooksSyncPayoutWorker

  setup :verify_on_exit!

  setup do
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

    :ok
  end

  describe "perform/1" do
    test "returns error when payout not found" do
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
  end
end
