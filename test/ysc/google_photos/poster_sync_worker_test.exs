defmodule Ysc.GooglePhotos.PosterSyncWorkerTest do
  use Ysc.DataCase, async: true

  import Ysc.EventsFixtures

  alias Ysc.GooglePhotos.PosterSyncWorker

  describe "when Google Photos is not connected" do
    test "enqueue_for_event/1 does nothing" do
      assert :ok = PosterSyncWorker.enqueue_for_event(event_fixture())
    end

    test "perform/1 skips the sync" do
      assert :ok = PosterSyncWorker.perform(%Oban.Job{})
    end
  end
end
