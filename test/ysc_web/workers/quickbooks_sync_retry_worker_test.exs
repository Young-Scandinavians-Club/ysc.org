defmodule YscWeb.Workers.QuickbooksSyncRetryWorkerTest do
  use Ysc.DataCase, async: false

  alias YscWeb.Workers.QuickbooksSyncRetryWorker

  describe "perform/1" do
    test "enqueues sync jobs for unsynced records" do
      job = %Oban.Job{
        id: 1,
        args: %{},
        worker: "YscWeb.Workers.QuickbooksSyncRetryWorker",
        queue: "maintenance",
        state: "available",
        attempt: 1
      }

      # Should complete successfully
      assert :ok = QuickbooksSyncRetryWorker.perform(job)
    end
  end
end
