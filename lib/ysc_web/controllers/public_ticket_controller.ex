defmodule YscWeb.PublicTicketController do
  @moduledoc """
  Sign-in-free ticket downloads linked from ticket emails.

  Every action is authorized by a signed `Ysc.Tickets.AccessToken` covering one
  ticket, so people without a YSC login (volunteers, guests a member bought a
  ticket for) can show their QR code and add it to Apple or Google Wallet.
  """
  # Dialyzer infers Passbook.generate/7 always returns {:error, :invalid_data}; see
  # AppleWalletController for the same suppression.
  @dialyzer {:nowarn_function, apple: 2}

  # Register @sobelow_skip so the Elixir compiler does not warn about the attribute
  # being unused (Sobelow consumes it from the source AST, not via Elixir reflection).
  Module.register_attribute(__MODULE__, :sobelow_skip, accumulate: true)

  use YscWeb, :controller

  require Ysc.Logging

  alias Ysc.AppleWallet
  alias Ysc.GoogleWallet
  alias Ysc.Scanning.QrToken
  alias Ysc.Tickets
  alias Ysc.Tickets.AccessToken

  @pkpass_content_type "application/vnd.apple.pkpass"

  @doc """
  Serves the ticket's check-in QR code as a PNG, for embedding in emails.
  """
  # send_resp delivers a generated PNG with an image content type, not HTML
  @sobelow_skip ["XSS.SendResp"]
  def qr_image(conn, %{"token" => token}) do
    with {:ok, ticket_id} <- AccessToken.verify_ticket(token),
         %{id: ^ticket_id} <- Tickets.get_check_in_ticket(ticket_id) do
      png =
        ticket_id
        |> QrToken.sign_ticket()
        |> EQRCode.encode()
        |> EQRCode.png(width: 400)

      conn
      |> put_resp_content_type("image/png")
      |> put_resp_header("cache-control", "private, max-age=86400")
      |> send_resp(200, png)
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  @doc """
  Downloads the ticket as an Apple Wallet pass.
  """
  # send_resp delivers a binary .pkpass file with a non-HTML content type and attachment disposition
  @sobelow_skip ["XSS.SendResp"]
  def apple(conn, %{"token" => token}) do
    with {:ok, ticket_id} <- AccessToken.verify_ticket(token),
         %{id: ^ticket_id} <- Tickets.get_check_in_ticket(ticket_id) do
      case AppleWallet.generate_ticket_pass(ticket_id, :any) do
        {:ok, binary} ->
          conn
          |> put_resp_content_type(@pkpass_content_type)
          |> put_resp_header(
            "content-disposition",
            "attachment; filename=\"ticket.pkpass\""
          )
          |> send_resp(200, binary)

        {:error, reason} when reason in [:not_configured, :not_found] ->
          YscWeb.ErrorHTML.render_page(conn, :"404")

        {:error, reason} ->
          Ysc.Logging.error(
            "PublicTicketController: failed to generate Apple Wallet pass",
            ticket_id: ticket_id,
            error: reason
          )

          YscWeb.ErrorHTML.render_page(conn, :"500")
      end
    else
      _ -> YscWeb.ErrorHTML.render_page(conn, :"404")
    end
  end

  @doc """
  Sends the visitor to Google Wallet's "Save to wallet" page for the ticket.
  """
  def google(conn, %{"token" => token}) do
    with {:ok, ticket_id} <- AccessToken.verify_ticket(token),
         %{id: ^ticket_id} <- Tickets.get_check_in_ticket(ticket_id) do
      case GoogleWallet.generate_ticket_save_url(ticket_id, :any) do
        {:ok, url} ->
          redirect(conn, external: url)

        {:error, reason} when reason in [:not_configured, :not_found] ->
          YscWeb.ErrorHTML.render_page(conn, :"404")

        {:error, reason} ->
          Ysc.Logging.error(
            "PublicTicketController: failed to generate Google Wallet URL",
            ticket_id: ticket_id,
            error: inspect(reason)
          )

          YscWeb.ErrorHTML.render_page(conn, :"500")
      end
    else
      _ -> YscWeb.ErrorHTML.render_page(conn, :"404")
    end
  end
end
