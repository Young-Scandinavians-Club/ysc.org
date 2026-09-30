defmodule YscWeb.WalletPlatform do
  @moduledoc """
  Interprets the WalletPlatform hook / connect_params platform string.

  Home, membership settings, and ticket QR previously copied the same
  `"apple_only"` / `"google_only"` / fallback-`:both` mapping for both
  LiveView connect params and the `wallet_platform_detected` hook event.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [connected?: 1, get_connect_params: 1]

  @doc """
  Maps the hook/connect-params string to a wallet-platform atom.

  Unknown, nil, and empty values fall back to `:both` (show every wallet
  button) so a missing or stale cache never hides a working badge.
  """
  def from_string("apple_only"), do: :apple_only
  def from_string("google_only"), do: :google_only
  def from_string(_), do: :both

  @doc """
  Reads `wallet_platform` from LiveView connect params.

  Falls back to `:both` on the disconnected render (no connect params)
  and on unknown values.
  """
  def from_socket(socket) do
    if connected?(socket) do
      from_string(get_connect_params(socket)["wallet_platform"])
    else
      :both
    end
  end

  @doc """
  Assigns `:wallet_platform` from a `wallet_platform_detected` hook payload.
  """
  def assign_from_hook(socket, platform) do
    assign(socket, :wallet_platform, from_string(platform))
  end
end
