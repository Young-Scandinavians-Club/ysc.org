defmodule Ysc.GooglePhotos.ApiTest do
  use ExUnit.Case, async: true

  import Ysc.GooglePhotos.Api.ReqTestHelper

  alias Ysc.GooglePhotos.Api
  alias Ysc.GooglePhotos.Limits

  @access_token "test-access-token"
  @stub stub()

  setup {Req.Test, :set_req_test_from_context}

  describe "create_album/3" do
    test "returns album id on success" do
      Req.Test.stub(@stub, stub_route(%{albums: &ok_album/1}))

      assert {:ok, "album-test-1"} =
               Api.create_album(@access_token, "  Summer Gala  ")
    end

    test "sends normalized title in JSON body" do
      Req.Test.stub(@stub, fn conn ->
        if path?(conn, :albums) do
          {body, conn} = read_json_body(conn)
          send(self(), {:album_body, body})
          ok_album(conn, "album-99")
        else
          Plug.Conn.send_resp(conn, 404, "unexpected")
        end
      end)

      assert {:ok, "album-99"} = Api.create_album(@access_token, "  Gala  ")

      assert_receive {:album_body, %{"album" => %{"title" => "Gala"}}}
    end

    test "includes bearer authorization header" do
      Req.Test.stub(@stub, fn conn ->
        if path?(conn, :albums) do
          send(self(), {:auth, req_header(conn, "authorization")})
          ok_album(conn)
        else
          Plug.Conn.send_resp(conn, 404, "unexpected")
        end
      end)

      token = @access_token
      assert {:ok, _} = Api.create_album(token, "Gala")
      assert_receive {:auth, "Bearer " <> ^token}
    end

    test "rejects empty title without calling the API" do
      assert {:error, :empty_album_title} =
               Api.create_album(@access_token, "   ")
    end

    test "returns api_error on non-success HTTP status" do
      Req.Test.stub(@stub, stub_route(%{albums: &api_error(&1, 403)}))

      assert {:error, {:api_error, 403}} =
               Api.create_album(@access_token, "Gala")
    end

    test "returns api_error when response body lacks album id" do
      Req.Test.stub(@stub, fn conn ->
        if path?(conn, :albums) do
          Req.Test.json(conn, %{"unexpected" => true})
        else
          Plug.Conn.send_resp(conn, 404, "unexpected")
        end
      end)

      assert {:error, {:api_error, 200}} =
               Api.create_album(@access_token, "Gala")
    end

    test "returns transport error when the request fails" do
      Req.Test.stub(@stub, fn conn ->
        if path?(conn, :albums) do
          Req.Test.transport_error(conn, :timeout)
        else
          Plug.Conn.send_resp(conn, 404, "unexpected")
        end
      end)

      assert {:error, %Req.TransportError{reason: :timeout}} =
               Api.create_album(@access_token, "Gala")
    end
  end

  describe "upload_bytes/4" do
    test "returns trimmed upload token" do
      Req.Test.stub(
        @stub,
        stub_route(%{uploads: fn conn -> ok_upload(conn, "tok\n") end})
      )

      assert {:ok, "tok"} =
               Api.upload_bytes(@access_token, "jpeg-bytes", "photo.jpg")
    end

    test "sends Google raw upload headers for byte payloads" do
      Req.Test.stub(@stub, fn conn ->
        if path?(conn, :uploads) do
          send(self(), {:upload_headers, req_headers_map(conn)})
          ok_upload(conn)
        else
          Plug.Conn.send_resp(conn, 404, "unexpected")
        end
      end)

      assert {:ok, _} =
               Api.upload_bytes(@access_token, "bytes", "party.png")

      assert_receive {:upload_headers, headers}

      assert headers["authorization"] == "Bearer #{@access_token}"
      assert headers["content-type"] == "application/octet-stream"
      assert headers["x-goog-upload-protocol"] == "raw"
      assert headers["x-goog-upload-content-type"] == "image/png"
      assert headers["x-goog-upload-file-name"] == "party.png"
      refute Map.has_key?(headers, "content-length")
    end

    test "maps video extensions to video content types" do
      Req.Test.stub(@stub, fn conn ->
        if path?(conn, :uploads) do
          send(
            self(),
            {:content_type, req_header(conn, "x-goog-upload-content-type")}
          )

          ok_upload(conn)
        else
          Plug.Conn.send_resp(conn, 404, "unexpected")
        end
      end)

      assert {:ok, _} = Api.upload_bytes(@access_token, "bytes", "clip.mp4")
      assert_receive {:content_type, "video/mp4"}
    end

    test "maps newly accepted photo and video extensions to correct content types" do
      Req.Test.stub(@stub, fn conn ->
        if path?(conn, :uploads) do
          send(
            self(),
            {:content_type, req_header(conn, "x-goog-upload-content-type")}
          )

          ok_upload(conn)
        else
          Plug.Conn.send_resp(conn, 404, "unexpected")
        end
      end)

      for {filename, expected_type} <- [
            {"photo.heif", "image/heif"},
            {"photo.bmp", "image/bmp"},
            {"photo.tif", "image/tiff"},
            {"photo.tiff", "image/tiff"},
            {"clip.3g2", "video/3gpp2"},
            {"clip.wmv", "video/x-ms-wmv"},
            {"clip.asf", "video/x-ms-asf"},
            {"clip.m2ts", "video/mp2t"},
            {"clip.mts", "video/mp2t"}
          ] do
        assert {:ok, _} = Api.upload_bytes(@access_token, "bytes", filename)
        assert_receive {:content_type, ^expected_type}
      end
    end

    test "rejects oversize photos before HTTP" do
      # Api.upload_bytes/3 gates on Limits.validate_upload/2 with byte_size/1
      # before any Req call. Pass size as an integer — never allocate 200MB.
      assert {:error, :photo_too_large} =
               Limits.validate_upload("big.jpg", Limits.max_photo_bytes() + 1)
    end

    test "rejects unsupported file types before HTTP" do
      assert {:error, :unsupported_type} =
               Api.upload_bytes(@access_token, "bytes", "notes.txt")
    end

    test "returns api_error on upload failure" do
      Req.Test.stub(@stub, stub_route(%{uploads: &api_error(&1, 400)}))

      assert {:error, {:api_error, 400}} =
               Api.upload_bytes(@access_token, "bytes", "photo.jpg")
    end

    test "returns api_error when upload token is empty" do
      Req.Test.stub(
        @stub,
        stub_route(%{uploads: fn conn -> ok_upload(conn, "") end})
      )

      assert {:error, {:api_error, 200}} =
               Api.upload_bytes(@access_token, "bytes", "photo.jpg")
    end
  end

  describe "create_media_item/4" do
    test "returns media item on batchCreate success" do
      Req.Test.stub(@stub, stub_route(%{batch_create: &ok_batch_create/1}))

      assert {:ok, %{"id" => "media-item-1"}} =
               Api.create_media_item(
                 @access_token,
                 "upload-token",
                 "album-1",
                 "photo.jpg"
               )
    end

    test "trims upload token and uses normalized filename in batchCreate body" do
      Req.Test.stub(@stub, fn conn ->
        if path?(conn, :batch_create) do
          {body, conn} = read_json_body(conn)
          send(self(), {:batch_body, body})
          ok_batch_create(conn)
        else
          Plug.Conn.send_resp(conn, 404, "unexpected")
        end
      end)

      assert {:ok, _} =
               Api.create_media_item(
                 @access_token,
                 " token-with-newline\n",
                 "album-1",
                 "/tmp/evil/photo.jpg"
               )

      assert_receive {:batch_body, body}

      assert %{
               "albumId" => "album-1",
               "newMediaItems" => [
                 %{
                   "description" => "photo.jpg",
                   "simpleMediaItem" => %{"uploadToken" => "token-with-newline"}
                 }
               ]
             } = body
    end

    test "returns media_item_failed when batch item status is not Success" do
      Req.Test.stub(@stub, fn conn ->
        if path?(conn, :batch_create) do
          Req.Test.json(conn, %{
            "newMediaItemResults" => [
              %{"status" => %{"message" => "Invalid upload token"}}
            ]
          })
        else
          Plug.Conn.send_resp(conn, 404, "unexpected")
        end
      end)

      assert {:error, :media_item_failed} =
               Api.create_media_item(
                 @access_token,
                 "bad-token",
                 "album-1",
                 "photo.jpg"
               )
    end

    test "returns api_error on batchCreate HTTP failure" do
      Req.Test.stub(@stub, stub_route(%{batch_create: &api_error(&1, 503)}))

      assert {:error, {:api_error, 503}} =
               Api.create_media_item(
                 @access_token,
                 "token",
                 "album-1",
                 "photo.jpg"
               )
    end
  end
end
