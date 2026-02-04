defmodule YscWeb.Workers.QuickbooksSyncRefundWorkerTest do
  use Ysc.DataCase, async: false

  import Mox

  alias YscWeb.Workers.QuickbooksSyncRefundWorker

  setup :verify_on_exit!

  setup do
    Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

    Application.put_env(:ysc, :quickbooks,
      client_id: "test_client_id",
      client_secret: "test_client_secret",
      company_id: "test_company_id",
      access_token: "test_access_token",
      refresh_token: "test_refresh_token"
    )

    :ok
  end

  describe "perform/1" do
    test "returns error when refund not found" do
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
  end
end
