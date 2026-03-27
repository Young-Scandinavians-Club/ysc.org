defmodule YscWeb.AppleWalletController do
  # Dialyzer infers Passbook.generate/7 always returns {:error, :invalid_data} (false positive
  # caused by the library's catch-all clause and an unresolvable :zip.create Erlang call),
  # which propagates here making {:ok, _binary} look unreachable.
  @dialyzer {:nowarn_function, ticket: 2, membership: 2}

  use YscWeb, :controller

  require Ysc.Logging

  alias Ysc.AppleWallet

  @pkpass_content_type "application/vnd.apple.pkpass"

  @doc """
  Generates and sends an Apple Wallet ticket pass (.pkpass) for a specific ticket.
  The current user must own the ticket and it must be confirmed.
  """
  def ticket(conn, %{"ticket_id" => ticket_id}) do
    user = conn.assigns.current_user

    case AppleWallet.generate_ticket_pass(ticket_id, user.id) do
      {:ok, binary} ->
        conn
        |> put_resp_content_type(@pkpass_content_type)
        |> put_resp_header(
          "content-disposition",
          "attachment; filename=\"ticket.pkpass\""
        )
        # sobelow_skip ["XSS.SendResp"] - binary is a .pkpass file served as an attachment with a non-HTML content type
        |> send_resp(200, binary)

      {:error, :not_configured} ->
        conn
        |> put_status(:not_found)
        |> put_view(html: YscWeb.ErrorHTML)
        |> render(:"404")

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> put_view(html: YscWeb.ErrorHTML)
        |> render(:"404")

      {:error, reason} ->
        Ysc.Logging.error(
          "AppleWalletController: failed to generate ticket pass",
          user_id: user.id,
          ticket_id: ticket_id,
          error: reason
        )

        conn
        |> put_status(:internal_server_error)
        |> put_view(html: YscWeb.ErrorHTML)
        |> render(:"500")
    end
  end

  @doc """
  Generates and sends an Apple Wallet membership pass (.pkpass) for the current user.
  The user must have an active membership.
  """
  def membership(conn, _params) do
    user = conn.assigns.current_user

    if conn.assigns[:active_membership?] do
      case AppleWallet.generate_membership_pass(user) do
        {:ok, binary} ->
          conn
          |> put_resp_content_type(@pkpass_content_type)
          |> put_resp_header(
            "content-disposition",
            "attachment; filename=\"membership.pkpass\""
          )
          # sobelow_skip ["XSS.SendResp"] - binary is a .pkpass file served as an attachment with a non-HTML content type
          |> send_resp(200, binary)

        {:error, :not_configured} ->
          conn
          |> put_status(:not_found)
          |> put_view(html: YscWeb.ErrorHTML)
          |> render(:"404")

        {:error, reason} ->
          Ysc.Logging.error(
            "AppleWalletController: failed to generate membership pass",
            user_id: user.id,
            error: reason
          )

          conn
          |> put_status(:internal_server_error)
          |> put_view(html: YscWeb.ErrorHTML)
          |> render(:"500")
      end
    else
      conn
      |> put_status(:not_found)
      |> put_view(html: YscWeb.ErrorHTML)
      |> render(:"404")
    end
  end
end
