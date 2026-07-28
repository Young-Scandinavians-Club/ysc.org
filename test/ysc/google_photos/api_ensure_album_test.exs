defmodule Ysc.GooglePhotos.Api.EnsureAlbumTest do
  use Ysc.DataCase, async: true

  import Ysc.EventsFixtures
  import Ysc.GooglePhotos.Api.ReqTestHelper

  alias Ysc.EventPhotos
  alias Ysc.EventPhotos.Collection
  alias Ysc.GooglePhotos.Api
  alias Ysc.GooglePhotos.Limits
  alias Ysc.Repo

  @access_token "test-access-token"
  @stub stub()

  setup {Req.Test, :set_req_test_from_context}

  setup do
    organizer = Ysc.AccountsFixtures.user_fixture()
    event = event_fixture(%{organizer_id: organizer.id})
    {:ok, collection} = EventPhotos.ensure_collection_for_event(event)

    %{event: event, collection: collection}
  end

  defp write_tmp_photo!(name, bytes) do
    path = Path.join(Ysc.SafeFile.event_photo_tmp_root(), name)
    File.write!(path, bytes)
    on_exit(fn -> File.rm(path) end)
    path
  end

  test "creates album, uploads bytes, and batchCreates media item", %{
    collection: collection,
    event: event
  } do
    path = write_tmp_photo!("small-#{System.unique_integer()}.jpg", "jpeg")

    {:ok, calls} = Agent.start_link(fn -> 0 end)

    Req.Test.stub(@stub, fn conn ->
      cond do
        path?(conn, :albums) ->
          Agent.update(calls, &(&1 + 1))
          ok_album(conn, "album-new")

        path?(conn, :uploads) ->
          Agent.update(calls, &(&1 + 1))
          ok_upload(conn, "byte-token")

        path?(conn, :batch_create) ->
          Agent.update(calls, &(&1 + 1))
          ok_batch_create(conn)

        true ->
          Plug.Conn.send_resp(conn, 404, "unexpected")
      end
    end)

    assert {:ok, "album-new"} =
             Api.ensure_album_and_upload(
               collection,
               event,
               @access_token,
               path,
               "photo.jpg"
             )

    assert Agent.get(calls, & &1) == 3

    updated = Repo.get!(Collection, collection.id)
    assert updated.google_album_id == "album-new"
  end

  test "skips album creation when google_album_id is already set", %{
    collection: collection,
    event: event
  } do
    {:ok, collection} =
      EventPhotos.set_google_album_id(collection, "existing-album")

    path = write_tmp_photo!("existing-#{System.unique_integer()}.jpg", "jpeg")

    {:ok, calls} = Agent.start_link(fn -> 0 end)

    Req.Test.stub(@stub, fn conn ->
      cond do
        path?(conn, :albums) ->
          Agent.update(calls, &(&1 + 1))
          ok_album(conn, "should-not-be-used")

        path?(conn, :uploads) ->
          Agent.update(calls, &(&1 + 1))
          ok_upload(conn)

        path?(conn, :batch_create) ->
          Agent.update(calls, &(&1 + 1))
          ok_batch_create(conn)

        true ->
          Plug.Conn.send_resp(conn, 404, "unexpected")
      end
    end)

    assert {:ok, "existing-album"} =
             Api.ensure_album_and_upload(
               collection,
               event,
               @access_token,
               path,
               "photo.jpg"
             )

    assert Agent.get(calls, & &1) == 2
  end

  test "streams large files with content-length and octet-stream headers", %{
    collection: collection,
    event: event
  } do
    size = Limits.max_photo_bytes() + 1

    path =
      write_sparse_tmp_file!(
        "stream-upload-#{System.unique_integer()}.mp4",
        size
      )

    on_exit(fn -> File.rm(path) end)

    Req.Test.stub(@stub, fn conn ->
      cond do
        path?(conn, :albums) ->
          ok_album(conn, "album-stream-1")

        path?(conn, :uploads) ->
          send(self(), {:stream_headers, req_headers_map(conn)})
          {body, conn} = read_entire_body(conn)
          send(self(), {:stream_body_size, byte_size(body)})
          ok_upload(conn, "stream-token")

        path?(conn, :batch_create) ->
          ok_batch_create(conn)

        true ->
          Plug.Conn.send_resp(conn, 404, "unexpected")
      end
    end)

    assert {:ok, "album-stream-1"} =
             Api.ensure_album_and_upload(
               collection,
               event,
               @access_token,
               path,
               "large-clip.mp4"
             )

    assert_receive {:stream_headers, headers}
    assert_receive {:stream_body_size, ^size}

    assert headers["content-type"] == "application/octet-stream"
    assert headers["x-goog-upload-content-type"] == "video/mp4"
    assert headers["x-goog-upload-file-name"] == "large-clip.mp4"
    assert headers["content-length"] == to_string(size)

    updated = Repo.get!(Collection, collection.id)
    assert updated.google_album_id == "album-stream-1"
  end

  test "rejects paths outside the event-photo tmp root", %{
    collection: collection,
    event: event
  } do
    assert {:error, :invalid_path} =
             Api.ensure_album_and_upload(
               collection,
               event,
               @access_token,
               "/etc/passwd",
               "photo.jpg"
             )
  end

  test "rejects oversize photos before HTTP", %{
    collection: collection,
    event: event
  } do
    size = Limits.max_photo_bytes() + 1

    path =
      write_sparse_tmp_file!("too-big-#{System.unique_integer()}.jpg", size)

    on_exit(fn -> File.rm(path) end)

    assert {:error, :photo_too_large} =
             Api.ensure_album_and_upload(
               collection,
               event,
               @access_token,
               path,
               "photo.jpg"
             )
  end

  test "propagates album API errors", %{collection: collection, event: event} do
    path = write_tmp_photo!("album-fail-#{System.unique_integer()}.jpg", "jpeg")

    Req.Test.stub(@stub, stub_route(%{albums: &api_error(&1, 401)}))

    assert {:error, {:api_error, 401}} =
             Api.ensure_album_and_upload(
               collection,
               event,
               @access_token,
               path,
               "photo.jpg"
             )
  end

  test "propagates upload API errors", %{collection: collection, event: event} do
    path =
      write_tmp_photo!("upload-fail-#{System.unique_integer()}.jpg", "jpeg")

    Req.Test.stub(@stub, fn conn ->
      cond do
        path?(conn, :albums) -> ok_album(conn)
        path?(conn, :uploads) -> api_error(conn, 400)
        true -> Plug.Conn.send_resp(conn, 404, "unexpected")
      end
    end)

    assert {:error, {:api_error, 400}} =
             Api.ensure_album_and_upload(
               collection,
               event,
               @access_token,
               path,
               "photo.jpg"
             )
  end

  test "propagates batchCreate API errors", %{
    collection: collection,
    event: event
  } do
    path = write_tmp_photo!("batch-fail-#{System.unique_integer()}.jpg", "jpeg")

    Req.Test.stub(@stub, fn conn ->
      cond do
        path?(conn, :albums) -> ok_album(conn)
        path?(conn, :uploads) -> ok_upload(conn)
        path?(conn, :batch_create) -> api_error(conn, 502)
        true -> Plug.Conn.send_resp(conn, 404, "unexpected")
      end
    end)

    assert {:error, {:api_error, 502}} =
             Api.ensure_album_and_upload(
               collection,
               event,
               @access_token,
               path,
               "photo.jpg"
             )
  end

end
