defmodule YscWeb.WalletPlatformTest do
  use ExUnit.Case, async: true

  alias YscWeb.WalletPlatform

  defp socket(assigns \\ %{}) do
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}}, assigns)
    }
  end

  describe "from_string/1" do
    test "maps known platform strings and falls back to both" do
      assert WalletPlatform.from_string("apple_only") == :apple_only
      assert WalletPlatform.from_string("google_only") == :google_only
      assert WalletPlatform.from_string("both") == :both
      assert WalletPlatform.from_string("unknown") == :both
      assert WalletPlatform.from_string(nil) == :both
    end
  end

  describe "from_socket/1" do
    test "returns both when the socket is not connected" do
      assert WalletPlatform.from_socket(socket()) == :both
    end
  end

  describe "assign_from_hook/2" do
    test "assigns the mapped wallet platform" do
      updated = WalletPlatform.assign_from_hook(socket(), "apple_only")

      assert updated.assigns.wallet_platform == :apple_only
    end
  end
end
