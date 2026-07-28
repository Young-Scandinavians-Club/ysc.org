defmodule Ysc.GooglePhotos.Api.DevStubRoutingTest do
  @moduledoc """
  Verifies Api routes to DevStub when configured.

  Runs synchronously because the routing decision reads global Application env
  and the singleton google_photos_connections row, which async tests can race on.
  """
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.GooglePhotos
  alias Ysc.GooglePhotos.Api

  setup do
    prev = Application.get_env(:ysc, :google_photos, [])

    Application.put_env(
      :ysc,
      :google_photos,
      Keyword.put(prev, :dev_stub, true)
    )

    on_exit(fn -> Application.put_env(:ysc, :google_photos, prev) end)

    GooglePhotos.disconnect!()

    :ok
  end

  test "create_album routes to DevStub when dev_stub is enabled and no connection exists" do
    organizer = user_fixture()
    event = event_fixture(%{organizer_id: organizer.id})

    assert {:ok, album_id} =
             Api.create_album("token", "Dev Album", event.id)

    assert String.starts_with?(album_id, "dev-album-")
  end
end
