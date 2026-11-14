defmodule YscWeb.GoogleWalletController do
  @moduledoc """
  Redirects a signed-in member to Google Wallet's "Save to wallet" page
  for a ticket they own.
  """
  use YscWeb, :controller

  require Ysc.Logging

  alias Ysc.GoogleWallet

  @doc """
  Generates a Google Wallet save URL for a specific ticket and redirects.

  The current user must own the ticket and it must be confirmed (and not a
  donation). Callers that already authorized access via a signed ticket token
  should use `YscWeb.PublicTicketController.google/2` instead.
  """
  def ticket(conn, %{"ticket_id" => ticket_id}) do
    user = conn.assigns.current_user

    case GoogleWallet.generate_ticket_save_url(ticket_id, user.id) do
      {:ok, url} ->
        redirect(conn, external: url)

      {:error, reason} when reason in [:not_configured, :not_found] ->
        YscWeb.ErrorHTML.render_page(conn, :"404")

      {:error, reason} ->
        Ysc.Logging.error(
          "GoogleWalletController: failed to generate ticket save URL",
          user_id: user.id,
          ticket_id: ticket_id,
          error: inspect(reason)
        )

        YscWeb.ErrorHTML.render_page(conn, :"500")
    end
  end
end
