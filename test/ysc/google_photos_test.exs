defmodule Ysc.GooglePhotosTest do
  use Ysc.DataCase, async: false

  alias Ysc.GooglePhotos
  alias Ysc.GooglePhotos.TokenStore

  import Ysc.AccountsFixtures

  describe "connection_status/0" do
    test "returns disconnected when no row exists" do
      status = GooglePhotos.connection_status()
      assert status.connected == false
      assert status.account_email == nil
      assert status.oauth_configured == GooglePhotos.OAuth.configured?()
    end
  end

  describe "connect!/3 and disconnect!/0" do
    test "stores encrypted connection and disconnect removes it" do
      user = user_fixture()

      GooglePhotos.connect!(
        %{
          access_token: "access",
          refresh_token: "refresh-token-value",
          expires_in: 3600,
          scope: "https://www.googleapis.com/auth/photoslibrary.appendonly"
        },
        user.id,
        "photos@example.com"
      )

      assert %{
               connected: true,
               account_email: "photos@example.com"
             } = GooglePhotos.connection_status()

      connection = GooglePhotos.get_connection()
      assert connection.refresh_token == "refresh-token-value"

      assert :ok = GooglePhotos.disconnect!()
      assert GooglePhotos.get_connection() == nil
      assert %{connected: false} = GooglePhotos.connection_status()
    end
  end

  describe "TokenStore" do
    test "returns :not_connected without a connection row" do
      assert {:error, :not_connected} = TokenStore.get_access_token()
    end
  end

  describe "configured?/0" do
    test "is true in test env with test credentials" do
      assert GooglePhotos.configured?()
    end
  end

  describe "OAuth.scopes_grant_complete?/1" do
    test "requires append, read, and edit app-created scopes" do
      assert Ysc.GooglePhotos.OAuth.scopes_grant_complete?(
               Enum.join(Ysc.GooglePhotos.OAuth.photos_api_scopes(), " ")
             )

      refute Ysc.GooglePhotos.OAuth.scopes_grant_complete?(
               "https://www.googleapis.com/auth/photoslibrary.readonly.appcreateddata"
             )
    end
  end
end
