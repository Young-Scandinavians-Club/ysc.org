defmodule Ysc.GooglePhotos.Api.ReqTestHelper do
  @moduledoc false

  @stub Ysc.GooglePhotos.Api.ReqStub

  @photos_paths %{
    albums: "/v1/albums",
    uploads: "/v1/uploads",
    batch_create: "/v1/mediaItems:batchCreate"
  }

  def stub, do: @stub

  def path?(conn, which) when which in [:albums, :uploads, :batch_create] do
    suffix = Map.fetch!(@photos_paths, which)
    String.ends_with?(conn.request_path, suffix)
  end

  def req_header(conn, name) do
    name = String.downcase(name)

    Enum.find_value(conn.req_headers, fn {key, value} ->
      if String.downcase(key) == name, do: value
    end)
  end

  def req_headers_map(conn) do
    Map.new(conn.req_headers, fn {k, v} -> {String.downcase(k), v} end)
  end

  def read_json_body(conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    {Jason.decode!(body), conn}
  end

  def read_entire_body(conn, acc \\ "") do
    case Plug.Conn.read_body(conn) do
      {:ok, body, conn} -> {acc <> body, conn}
      {:more, partial, conn} -> read_entire_body(conn, acc <> partial)
      {:error, reason} -> {:error, reason}
    end
  end

  def route(conn, handlers) when is_map(handlers) do
    cond do
      path?(conn, :albums) and Map.has_key?(handlers, :albums) ->
        handlers[:albums].(conn)

      path?(conn, :uploads) and Map.has_key?(handlers, :uploads) ->
        handlers[:uploads].(conn)

      path?(conn, :batch_create) and Map.has_key?(handlers, :batch_create) ->
        handlers[:batch_create].(conn)

      true ->
        Plug.Conn.send_resp(conn, 404, "no stub for #{conn.request_path}")
    end
  end

  def stub_route(handlers) when is_map(handlers) do
    fn conn -> route(conn, handlers) end
  end

  def ok_album(conn, album_id \\ "album-test-1") do
    Req.Test.json(conn, %{"id" => album_id})
  end

  def ok_upload(conn, token \\ "upload-token-abc") do
    Req.Test.text(conn, token)
  end

  def ok_batch_create(conn, media_item_id \\ "media-item-1") do
    Req.Test.json(conn, %{
      "newMediaItemResults" => [
        %{
          "status" => %{"message" => "Success"},
          "mediaItem" => %{"id" => media_item_id}
        }
      ]
    })
  end

  def api_error(conn, status, body \\ %{"error" => %{"message" => "failed"}}) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  @doc "Writes a sparse file of `size` bytes under the event-photo tmp root."
  def write_sparse_tmp_file!(filename, size)
      when is_integer(size) and size > 0 do
    root = Ysc.SafeFile.event_photo_tmp_root()
    path = Path.join(root, filename)
    File.mkdir_p!(Path.dirname(path))

    {:ok, fd} = File.open(path, [:write, :raw])
    {:ok, _} = :file.position(fd, size - 1)
    :ok = :file.write(fd, "x")
    :ok = File.close(fd)

    path
  end
end
