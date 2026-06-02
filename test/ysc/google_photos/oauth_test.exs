defmodule Ysc.GooglePhotos.OAuthTest do
  use ExUnit.Case, async: true

  import Ysc.GooglePhotos.OAuth.ReqTestHelper

  alias Ysc.GooglePhotos.OAuth

  @stub stub()

  setup {Req.Test, :set_req_test_from_context}

  describe "exchange_code/1" do
    test "returns parsed tokens on success" do
      Req.Test.stub(@stub, fn conn ->
        if token_url?(conn) do
          ok_token_response(conn,
            access_token: "exchanged-access",
            refresh_token: "exchanged-refresh",
            expires_in: 7200
          )
        else
          Plug.Conn.send_resp(conn, 404, "unexpected")
        end
      end)

      assert {:ok,
              %{
                access_token: "exchanged-access",
                refresh_token: "exchanged-refresh",
                expires_in: 7200,
                token_type: "Bearer"
              }} = OAuth.exchange_code("auth-code")
    end

    test "returns invalid_grant when Google revokes the code" do
      Req.Test.stub(@stub, fn conn ->
        if token_url?(conn),
          do: token_error(conn, "invalid_grant"),
          else: Plug.Conn.send_resp(conn, 404, "")
      end)

      assert {:error, :invalid_grant} = OAuth.exchange_code("bad-code")
    end
  end

  describe "refresh_access_token/1" do
    test "returns a new access token" do
      Req.Test.stub(@stub, fn conn ->
        if token_url?(conn) do
          ok_token_response(conn,
            access_token: "refreshed-access",
            expires_in: 3600
          )
        else
          Plug.Conn.send_resp(conn, 404, "unexpected")
        end
      end)

      assert {:ok, %{access_token: "refreshed-access", expires_in: 3600}} =
               OAuth.refresh_access_token("stored-refresh")
    end

    test "returns invalid_grant for revoked refresh tokens" do
      Req.Test.stub(@stub, fn conn ->
        if token_url?(conn),
          do: token_error(conn, "invalid_grant"),
          else: Plug.Conn.send_resp(conn, 404, "")
      end)

      assert {:error, :invalid_grant} =
               OAuth.refresh_access_token("revoked-refresh")
    end

    test "includes rotated refresh token when Google returns one" do
      Req.Test.stub(@stub, fn conn ->
        if token_url?(conn) do
          ok_token_response(conn,
            access_token: "refreshed-access",
            refresh_token: "rotated-refresh",
            expires_in: 3600
          )
        else
          Plug.Conn.send_resp(conn, 404, "unexpected")
        end
      end)

      assert {:ok, %{refresh_token: "rotated-refresh"}} =
               OAuth.refresh_access_token("stored-refresh")
    end
  end

  describe "fetch_userinfo/1" do
    test "returns email on success" do
      Req.Test.stub(@stub, fn conn ->
        if userinfo_url?(conn),
          do: ok_userinfo(conn, "org@example.com"),
          else: Plug.Conn.send_resp(conn, 404, "")
      end)

      assert {:ok, "org@example.com"} = OAuth.fetch_userinfo("access-token")
    end
  end

  describe "test_photos_api/1" do
    test "returns ok when albums list succeeds" do
      Req.Test.stub(@stub, fn conn ->
        if albums_url?(conn),
          do: ok_albums(conn),
          else: Plug.Conn.send_resp(conn, 404, "unexpected")
      end)

      assert :ok = OAuth.test_photos_api("access-token")
    end

    test "returns insufficient_scopes when Google reports insufficient permissions" do
      Req.Test.stub(@stub, fn conn ->
        if albums_url?(conn) do
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(
            403,
            Jason.encode!(%{
              "error" => %{
                "message" => "Request had insufficient authentication scopes."
              }
            })
          )
        else
          Plug.Conn.send_resp(conn, 404, "unexpected")
        end
      end)

      assert {:error, :insufficient_scopes} =
               OAuth.test_photos_api("access-token")
    end
  end

  describe "authorize_url/1" do
    test "includes offline access and consent prompt" do
      url = OAuth.authorize_url("state-123")
      assert is_binary(url)
      assert url =~ "access_type=offline"
      assert url =~ "prompt=consent"
      assert url =~ "state=state-123"
      assert url =~ "photoslibrary.appendonly"
    end
  end
end
