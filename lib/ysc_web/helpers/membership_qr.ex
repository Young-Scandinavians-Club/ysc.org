defmodule YscWeb.MembershipQr do
  @moduledoc """
  Shared LiveView assign helpers for `<.membership_qr_modal>`.

  Home and membership settings previously copied the same show/hide
  assign updates (`:show_membership_qr`, `:membership_qr_token`,
  `:membership_qr_details`). Google Wallet save-URL JWTs are generated on
  click at `/wallet/membership/google`, matching Apple Wallet.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Ysc.Scanning.QrToken
  alias YscWeb.MembershipHelpers

  @doc """
  Opens the membership QR modal: signs a token and builds details.

  Does not query subscriptions or sign a Google Wallet JWT. The modal
  links to `/wallet/membership/google` when Google Wallet is enabled.
  """
  def show(socket, user) do
    socket
    |> assign(:show_membership_qr, true)
    |> assign(:membership_qr_token, QrToken.sign_membership(user.id))
    |> assign(
      :membership_qr_details,
      MembershipHelpers.build_membership_qr_details(socket.assigns)
    )
  end

  @doc """
  Closes the membership QR modal and clears the signed token and details.
  """
  def hide(socket) do
    socket
    |> assign(:show_membership_qr, false)
    |> assign(:membership_qr_token, nil)
    |> assign(:membership_qr_details, nil)
  end
end
