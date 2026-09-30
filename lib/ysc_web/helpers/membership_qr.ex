defmodule YscWeb.MembershipQr do
  @moduledoc """
  Shared LiveView assign helpers for `<.membership_qr_modal>`.

  Home and membership settings previously copied the same show/hide
  assign updates (`:show_membership_qr`, `:membership_qr_token`,
  `:membership_qr_details`, `:google_wallet_membership_url`).
  """

  import Phoenix.Component, only: [assign: 3]

  alias Ysc.GoogleWallet
  alias Ysc.Scanning.QrToken
  alias YscWeb.MembershipHelpers

  @doc """
  Opens the membership QR modal: signs a token, builds details, and
  optionally generates a Google Wallet save URL.
  """
  def show(socket, user) do
    socket
    |> assign(:show_membership_qr, true)
    |> assign(:membership_qr_token, QrToken.sign_membership(user.id))
    |> assign(
      :membership_qr_details,
      MembershipHelpers.build_membership_qr_details(socket.assigns)
    )
    |> assign(:google_wallet_membership_url, google_wallet_url(socket, user))
  end

  @doc """
  Closes the membership QR modal and clears the signed token and details.

  Leaves `:google_wallet_membership_url` assigned, matching the previous
  home/settings hide handlers.
  """
  def hide(socket) do
    socket
    |> assign(:show_membership_qr, false)
    |> assign(:membership_qr_token, nil)
    |> assign(:membership_qr_details, nil)
  end

  defp google_wallet_url(socket, user) do
    if socket.assigns.google_wallet_membership_enabled? do
      case GoogleWallet.generate_membership_save_url(user) do
        {:ok, url} -> url
        _ -> nil
      end
    end
  end
end
