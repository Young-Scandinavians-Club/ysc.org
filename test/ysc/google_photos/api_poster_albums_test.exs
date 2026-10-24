defmodule Ysc.GooglePhotos.ApiPosterAlbumsTest do
  use ExUnit.Case, async: true

  import Ysc.GooglePhotos.Api.ReqTestHelper

  alias Ysc.GooglePhotos.Api

  @access_token "test-access-token"
  @stub stub()

  setup {Req.Test, :set_req_test_from_context}

  describe "list_albums/1" do
    test "follows pagination and returns every album" do
      Req.Test.stub(@stub, fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        send(self(), {:auth, req_header(conn, "authorization")})

        case params["pageToken"] do
          nil ->
            Req.Test.json(conn, %{
              "albums" => [%{"id" => "a1", "title" => "One"}],
              "nextPageToken" => "page-2"
            })

          "page-2" ->
            Req.Test.json(conn, %{
              "albums" => [%{"id" => "a2", "title" => "Two"}]
            })
        end
      end)

      assert {:ok, [%{"id" => "a1"}, %{"id" => "a2"}]} =
               Api.list_albums(@access_token)

      assert_received {:auth, "Bearer test-access-token"}
    end

    test "returns an empty list when the account has no app-created albums" do
      Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, %{}) end)
      assert {:ok, []} = Api.list_albums(@access_token)
    end

    test "returns api_error on failure" do
      Req.Test.stub(@stub, &api_error(&1, 403))
      assert {:error, {:api_error, 403}} = Api.list_albums(@access_token)
    end
  end

  describe "remove_media_items/3" do
    test "posts the media item ids to the album" do
      Req.Test.stub(@stub, fn conn ->
        {body, conn} = read_json_body(conn)
        send(self(), {:removed, conn.request_path, body})
        Req.Test.json(conn, %{})
      end)

      assert :ok =
               Api.remove_media_items(@access_token, "album-1", ["m1", "m2"])

      assert_received {:removed, "/v1/albums/album-1:batchRemoveMediaItems",
                       %{"mediaItemIds" => ["m1", "m2"]}}
    end

    test "does not call the API when there is nothing to remove" do
      assert :ok = Api.remove_media_items(@access_token, "album-1", [])
    end

    test "returns api_error on failure" do
      Req.Test.stub(@stub, &api_error(&1, 400))

      assert {:error, {:api_error, 400}} =
               Api.remove_media_items(@access_token, "album-1", ["m1"])
    end
  end
end
