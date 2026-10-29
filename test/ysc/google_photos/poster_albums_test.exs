defmodule Ysc.GooglePhotos.PosterAlbumsTest do
  use Ysc.DataCase, async: true

  import Ysc.EventsFixtures

  alias Ysc.GooglePhotos.Api.ReqTestHelper
  alias Ysc.GooglePhotos.PosterAlbum
  alias Ysc.GooglePhotos.PosterAlbums
  alias Ysc.GooglePhotos.PosterItem
  alias Ysc.Repo

  @access_token "test-access-token"
  @stub ReqTestHelper.stub()

  setup {Req.Test, :set_req_test_from_context}

  # A tiny fake of the Photos Library API. Every call is reported to the test
  # process so tests can assert exactly what we sent to Google.
  defp stub_google(opts \\ []) do
    existing_albums = Keyword.get(opts, :albums, [])
    fail = Keyword.get(opts, :fail, %{})

    Req.Test.stub(@stub, fn conn ->
      {body, conn} = read_body(conn)
      route = {conn.method, route_key(conn.request_path)}

      case Map.fetch(fail, route) do
        {:ok, status} ->
          ReqTestHelper.api_error(conn, status)

        :error ->
          respond(conn, route, body, existing_albums)
      end
    end)
  end

  defp route_key("/v1/albums/" <> rest) do
    if String.ends_with?(rest, ":batchRemoveMediaItems"),
      do: :remove_media_items,
      else: :unknown
  end

  defp route_key("/v1/albums"), do: :albums
  defp route_key("/v1/uploads"), do: :uploads
  defp route_key("/v1/mediaItems:batchCreate"), do: :batch_create
  defp route_key(_), do: :unknown

  defp respond(conn, {"GET", :albums}, _body, existing_albums) do
    send(self(), :list_albums)
    Req.Test.json(conn, %{"albums" => existing_albums})
  end

  defp respond(conn, {"POST", :albums}, body, _existing_albums) do
    %{"album" => %{"title" => title}} = Jason.decode!(body)
    send(self(), {:create_album, title})

    Req.Test.json(conn, %{"id" => "album-#{System.unique_integer([:positive])}"})
  end

  defp respond(conn, {"POST", :uploads}, _body, _existing_albums) do
    send(self(), :upload)
    Req.Test.text(conn, "upload-#{System.unique_integer([:positive])}")
  end

  defp respond(conn, {"POST", :batch_create}, body, _existing_albums) do
    %{"albumId" => album_id} = Jason.decode!(body)
    send(self(), {:batch_create, album_id})

    ReqTestHelper.ok_batch_create(
      conn,
      "media-#{System.unique_integer([:positive])}"
    )
  end

  defp respond(conn, {"POST", :remove_media_items}, body, _existing_albums) do
    send(self(), {:remove_media_items, conn.request_path, Jason.decode!(body)})
    Req.Test.json(conn, %{})
  end

  defp read_body(conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    {body, conn}
  end

  defp flush_messages(acc \\ []) do
    receive do
      message -> flush_messages([message | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp past_event_fixture(attrs \\ %{}) do
    event_fixture(
      Map.merge(
        %{
          start_date: DateTime.add(DateTime.utc_now(), -10, :day),
          end_date: DateTime.add(DateTime.utc_now(), -9, :day)
        },
        attrs
      )
    )
  end

  defp items_for(event),
    do: Repo.all(from i in PosterItem, where: i.event_id == ^event.id)

  describe "list_tv_poster_events/0" do
    test "returns only published events that have not ended" do
      upcoming = event_fixture()
      _draft = event_fixture(%{state: :draft})
      _cancelled = event_fixture(%{state: :cancelled})
      _past = past_event_fixture()

      assert [%{id: id}] = Ysc.Events.list_tv_poster_events()
      assert id == upcoming.id
    end

    test "slims event-body HTML and batch-enriches pricing for every upcoming event" do
      events =
        Enum.map(1..3, fn index ->
          event =
            event_fixture(%{
              title: "Poster batch #{index}",
              raw_details: "<p>must not load poster body #{index}</p>",
              rendered_details: "<p>must not load poster html #{index}</p>"
            })

          ticket_tier_fixture(%{event_id: event.id})
          event
        end)

      {loaded, body_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn -> Ysc.Events.list_tv_poster_events() end,
          pattern: ~r/raw_details|rendered_details/i,
          caller_pids: [self()]
        )

      {_loaded, tier_selects} =
        Ysc.QueryCounter.with_query_counter(
          fn -> Ysc.Events.list_tv_poster_events() end,
          pattern: ~r/FROM "ticket_tiers"/i,
          caller_pids: [self()]
        )

      loaded_ids = MapSet.new(Enum.map(loaded, & &1.id))
      expected_ids = MapSet.new(Enum.map(events, & &1.id))

      assert MapSet.subset?(expected_ids, loaded_ids)
      assert Enum.all?(loaded, &is_nil(&1.raw_details))
      assert Enum.all?(loaded, &is_nil(&1.rendered_details))
      assert Enum.all?(loaded, &is_map(&1.pricing_info))
      assert body_cols == 0
      assert tier_selects == 1
    end
  end

  describe "sync/1" do
    test "creates the display and generic albums and adds the poster to each" do
      stub_google()
      event = event_fixture()

      assert {:ok, %{published: 3, removed: 0}} =
               PosterAlbums.sync(access_token: @access_token)

      messages = flush_messages()
      assert {:create_album, "Tahoe Display Album"} in messages
      assert {:create_album, "Clear Lake Display Album"} in messages
      assert {:create_album, "Upcoming YSC Events"} in messages

      albums = Repo.all(PosterAlbum)

      assert Enum.sort(Enum.map(albums, & &1.key)) == [
               :clear_lake,
               :tahoe,
               :upcoming
             ]

      items = items_for(event)

      assert Enum.sort(Enum.map(items, & &1.key)) == [
               :clear_lake,
               :tahoe,
               :upcoming
             ]

      assert Enum.sort(Enum.map(items, & &1.google_album_id)) ==
               Enum.sort(Enum.map(albums, & &1.google_album_id))
    end

    test "does nothing the second time when posters are unchanged" do
      stub_google()
      _event = event_fixture()

      assert {:ok, %{published: 3}} =
               PosterAlbums.sync(access_token: @access_token)

      flush_messages()

      assert {:ok, %{published: 0, removed: 0}} =
               PosterAlbums.sync(access_token: @access_token)

      assert flush_messages() == []
    end

    test "reuses an existing album with the same title instead of creating one" do
      stub_google(
        albums: [
          %{"id" => "existing-tahoe", "title" => "Tahoe Display Album"}
        ]
      )

      assert {:ok, _} = PosterAlbums.sync(access_token: @access_token)

      messages = flush_messages()
      refute {:create_album, "Tahoe Display Album"} in messages
      assert {:create_album, "Clear Lake Display Album"} in messages
      assert {:create_album, "Upcoming YSC Events"} in messages

      assert Repo.get_by!(PosterAlbum, key: :tahoe).google_album_id ==
               "existing-tahoe"
    end

    test "replaces the poster when the event changes" do
      stub_google()
      event = event_fixture()
      assert {:ok, _} = PosterAlbums.sync(access_token: @access_token)
      flush_messages()

      old_ids =
        event |> items_for() |> Map.new(&{&1.key, &1.media_item_id})

      {:ok, _} = Ysc.Events.update_event(event, %{title: "A Brand New Title"})

      assert {:ok, %{published: 3, removed: 0}} =
               PosterAlbums.sync(access_token: @access_token)

      new_items = items_for(event)
      assert length(new_items) == 3

      for item <- new_items do
        refute item.media_item_id == old_ids[item.key]
      end

      removals =
        for {:remove_media_items, _path, body} <- flush_messages(),
            do: body["mediaItemIds"]

      assert Enum.sort(List.flatten(removals)) == Enum.sort(Map.values(old_ids))
    end

    test "removes the poster once the event is over, leaving other items alone" do
      stub_google()
      live = event_fixture()
      assert {:ok, _} = PosterAlbums.sync(access_token: @access_token)

      over = past_event_fixture()
      album = Repo.get_by!(PosterAlbum, key: :tahoe)

      Repo.insert!(%PosterItem{
        event_id: over.id,
        key: :tahoe,
        google_album_id: album.google_album_id,
        media_item_id: "media-over",
        poster_hash: "stale"
      })

      flush_messages()

      assert {:ok, %{published: 0, removed: 1}} =
               PosterAlbums.sync(access_token: @access_token)

      assert [{:remove_media_items, path, %{"mediaItemIds" => ["media-over"]}}] =
               flush_messages()

      assert path =~ album.google_album_id
      assert items_for(over) == []
      assert length(items_for(live)) == 3
    end

    test "removes the poster when an event is cancelled" do
      stub_google()
      event = event_fixture()
      assert {:ok, _} = PosterAlbums.sync(access_token: @access_token)
      flush_messages()

      {:ok, _} = Ysc.Events.cancel_event(event, actor: :system)

      assert {:ok, %{removed: 3}} =
               PosterAlbums.sync(access_token: @access_token)

      assert items_for(event) == []
    end

    test "treats an item Google no longer has as already removed" do
      stub_google(fail: %{{"POST", :remove_media_items} => 404})
      event = event_fixture()
      assert {:ok, _} = PosterAlbums.sync(access_token: @access_token)

      {:ok, _} = Ysc.Events.cancel_event(event, actor: :system)

      assert {:ok, %{removed: 3}} =
               PosterAlbums.sync(access_token: @access_token)

      assert items_for(event) == []
    end

    test "keeps the record and reports an error when removal fails" do
      stub_google(fail: %{{"POST", :remove_media_items} => 500})
      event = event_fixture()
      assert {:ok, _} = PosterAlbums.sync(access_token: @access_token)

      {:ok, _} = Ysc.Events.cancel_event(event, actor: :system)

      assert {:error, {:sync_failed, _}} =
               PosterAlbums.sync(access_token: @access_token)

      assert length(items_for(event)) == 3
    end

    test "records nothing and reports an error when the upload fails" do
      stub_google(fail: %{{"POST", :uploads} => 500})
      event = event_fixture()

      assert {:error, {:sync_failed, errors}} =
               PosterAlbums.sync(access_token: @access_token)

      assert length(errors) == 3
      assert items_for(event) == []
    end

    test "never raises when Google misbehaves" do
      Req.Test.stub(@stub, fn _conn -> raise "boom" end)
      _event = event_fixture()

      assert {:error, _reason} = PosterAlbums.sync(access_token: @access_token)
    end

    test "returns the credential error when Google Photos is not connected" do
      assert {:error, :not_connected} = PosterAlbums.sync()
    end
  end

  describe "has_items?/1" do
    test "is true only for events with a recorded poster" do
      stub_google()
      event = event_fixture()
      other = event_fixture(%{state: :draft})
      refute PosterAlbums.has_items?(event.id)

      assert {:ok, _} = PosterAlbums.sync(access_token: @access_token)
      assert PosterAlbums.has_items?(event.id)
      refute PosterAlbums.has_items?(other.id)
    end
  end
end
