defmodule Ysc.GooglePhotos.PosterSyncDevStubTest do
  # Not async: flips global app config so Google Photos counts as available
  # (via the dev stub, so no HTTP). Oban runs jobs inline in tests, so saving an
  # event runs the whole sync before the call returns.
  use Ysc.DataCase, async: false

  import Ysc.EventsFixtures

  alias Ysc.Events
  alias Ysc.GooglePhotos.PosterAlbums
  alias Ysc.GooglePhotos.PosterSyncWorker

  setup do
    original = Application.get_env(:ysc, :google_photos, [])

    Application.put_env(
      :ysc,
      :google_photos,
      Keyword.put(original, :dev_stub, true)
    )

    on_exit(fn ->
      Application.put_env(:ysc, :google_photos, original)
      File.rm_rf("tmp/dev_event_photos")
    end)

    :ok
  end

  test "publishing and cancelling an event adds and removes its posters" do
    event = event_fixture()
    assert PosterAlbums.has_items?(event.id)

    assert {:ok, _} = Events.cancel_event(event)
    refute PosterAlbums.has_items?(event.id)
  end

  test "draft events with no posters are ignored" do
    event = event_fixture(%{state: :draft})

    assert :ok = PosterSyncWorker.enqueue_for_event(event)
    refute PosterAlbums.has_items?(event.id)
  end

  test "unpublishing an event that already has posters still removes them" do
    event = event_fixture()
    assert PosterAlbums.has_items?(event.id)

    assert {:ok, draft} = Events.unpublish_event(event)
    assert draft.state == :draft
    refute PosterAlbums.has_items?(event.id)
  end

  test "a failing poster capture is swallowed" do
    original = Application.get_env(:ysc, :tv_poster_image_module)

    Application.put_env(
      :ysc,
      :tv_poster_image_module,
      Ysc.Events.TvPosterImage.ErrorStub
    )

    on_exit(fn ->
      Application.put_env(:ysc, :tv_poster_image_module, original)
    end)

    event = event_fixture()

    assert :ok = PosterSyncWorker.enqueue_for_event(event)
    assert :ok = PosterSyncWorker.perform(%Oban.Job{})
    refute PosterAlbums.has_items?(event.id)
  end
end
