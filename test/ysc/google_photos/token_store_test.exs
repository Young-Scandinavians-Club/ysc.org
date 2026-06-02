defmodule Ysc.GooglePhotos.TokenStoreTest do
  use Ysc.DataCase, async: false

  import Ysc.GooglePhotos.OAuth.ReqTestHelper

  alias Ysc.GooglePhotos
  alias Ysc.GooglePhotos.TokenStore

  @stub stub()

  setup {Req.Test, :set_req_test_from_context}

  setup %{sandbox_owner: owner} do
    if token_store_pid = Process.whereis(TokenStore) do
      :ok = Ecto.Adapters.SQL.Sandbox.allow(Ysc.Repo, owner, token_store_pid)
    end

    :ok
  end

  describe "get_access_token/0" do
    test "returns :not_connected without a connection row" do
      assert {:error, :not_connected} = TokenStore.get_access_token()
    end

    test "returns primed access token without calling the token endpoint" do
      user = Ysc.AccountsFixtures.user_fixture()

      GooglePhotos.connect!(
        %{
          access_token: "primed-access",
          refresh_token: "refresh-abc",
          expires_in: 3600,
          scope: Enum.join(GooglePhotos.OAuth.photos_api_scopes(), " ")
        },
        user.id,
        "photos@example.com"
      )

      test_pid = self()

      Req.Test.stub(@stub, fn conn ->
        if token_url?(conn) do
          send(test_pid, :unexpected_token_refresh)
          ok_token_response(conn)
        else
          Plug.Conn.send_resp(conn, 404, "unexpected")
        end
      end)

      assert {:ok, "primed-access"} = TokenStore.get_access_token()
      refute_received :unexpected_token_refresh
    end

    test "refreshes expired tokens and caches the new access token" do
      user = Ysc.AccountsFixtures.user_fixture()

      GooglePhotos.connect!(
        %{
          access_token: "stale-access",
          refresh_token: "refresh-abc",
          expires_in: 3600,
          scope: Enum.join(GooglePhotos.OAuth.photos_api_scopes(), " ")
        },
        user.id,
        "photos@example.com"
      )

      :ok = TokenStore.prime("stale-access", 0, "refresh-abc")

      Req.Test.stub(@stub, fn conn ->
        if token_url?(conn) do
          ok_token_response(conn,
            access_token: "fresh-access",
            expires_in: 3600
          )
        else
          Plug.Conn.send_resp(conn, 404, "unexpected")
        end
      end)

      assert {:ok, "fresh-access"} = TokenStore.get_access_token()
      assert {:ok, "fresh-access"} = TokenStore.get_access_token()
    end

    test "persists rotated refresh tokens from Google" do
      user = Ysc.AccountsFixtures.user_fixture()

      GooglePhotos.connect!(
        %{
          access_token: "access",
          refresh_token: "refresh-old",
          expires_in: 3600,
          scope: Enum.join(GooglePhotos.OAuth.photos_api_scopes(), " ")
        },
        user.id,
        "photos@example.com"
      )

      :ok = TokenStore.prime("access", 0, "refresh-old")

      Req.Test.stub(@stub, fn conn ->
        if token_url?(conn) do
          ok_token_response(conn,
            access_token: "fresh-access",
            refresh_token: "refresh-new",
            expires_in: 3600
          )
        else
          Plug.Conn.send_resp(conn, 404, "unexpected")
        end
      end)

      assert {:ok, "fresh-access"} = TokenStore.get_access_token()
      assert GooglePhotos.get_connection().refresh_token == "refresh-new"
    end

    test "disconnects and returns :refresh_token_revoked on invalid_grant" do
      user = Ysc.AccountsFixtures.user_fixture()

      GooglePhotos.connect!(
        %{
          access_token: "access",
          refresh_token: "refresh-revoked",
          expires_in: 3600,
          scope: Enum.join(GooglePhotos.OAuth.photos_api_scopes(), " ")
        },
        user.id,
        "photos@example.com"
      )

      :ok = TokenStore.prime("access", 0, "refresh-revoked")

      Req.Test.stub(@stub, fn conn ->
        if token_url?(conn),
          do: token_error(conn, "invalid_grant"),
          else: Plug.Conn.send_resp(conn, 404, "")
      end)

      assert {:error, :refresh_token_revoked} = TokenStore.get_access_token()
      assert GooglePhotos.get_connection() == nil
      assert %{connected: false} = GooglePhotos.connection_status()
    end
  end

  describe "reload/0" do
    test "clears cached tokens so the next call refreshes" do
      user = Ysc.AccountsFixtures.user_fixture()

      GooglePhotos.connect!(
        %{
          access_token: "primed-access",
          refresh_token: "refresh-abc",
          expires_in: 3600,
          scope: Enum.join(GooglePhotos.OAuth.photos_api_scopes(), " ")
        },
        user.id,
        "photos@example.com"
      )

      TokenStore.reload()

      Req.Test.stub(@stub, fn conn ->
        if token_url?(conn) do
          ok_token_response(conn,
            access_token: "after-reload",
            expires_in: 3600
          )
        else
          Plug.Conn.send_resp(conn, 404, "unexpected")
        end
      end)

      assert {:ok, "after-reload"} = TokenStore.get_access_token()
    end
  end
end
