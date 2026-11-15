defmodule YscWeb.GoogleWalletController do
  @moduledoc """
  Redirects a signed-in member to Google Wallet's "Save to wallet" page
  for their membership card.

  JWT signing and the subscription lookup happen here, on click — not while
  the membership QR modal opens. Ticket save links use
  `YscWeb.PublicTicketController.google/2` (email token) or a member ticket
  route when that exists.
  """
  use YscWeb, :controller

  require Ysc.Logging

  alias Ysc.GoogleWallet

  @doc """
  Generates a Google Wallet save URL for the current member and redirects.

  The user must have an active membership (same gate as Apple Wallet).
  """
  def membership(conn, _params) do
    user = conn.assigns.current_user

    if conn.assigns[:active_membership?] do
      case GoogleWallet.generate_membership_save_url(user) do
        {:ok, url} ->
          redirect(conn, external: url)

        {:error, reason} when reason in [:not_configured, :not_found] ->
          YscWeb.ErrorHTML.render_page(conn, :"404")

        {:error, reason} ->
          Ysc.Logging.error(
            "GoogleWalletController: failed to generate membership save URL",
            user_id: user.id,
            error: inspect(reason)
          )

          YscWeb.ErrorHTML.render_page(conn, :"500")
      end
    else
      YscWeb.ErrorHTML.render_page(conn, :"404")
    end
  end
end
