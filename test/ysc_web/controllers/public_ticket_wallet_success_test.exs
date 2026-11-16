defmodule YscWeb.PublicTicketWalletSuccessTest do
  @moduledoc """
  Sign-in-free Apple Wallet download from a ticket email.

  Google's `/t/:token/google` success path is covered in
  `public_ticket_live_test.exs`. Apple's matching HTTP path was only
  404-tested; a `:any` → `current_user.id` swap would break guests without
  failing those tests.

  async: false — `with_fake_certs/1` mutates CertManager and app env.
  """
  use YscWeb.ConnCase, async: false

  import Ysc.AccountsFixtures
  import Ysc.AppleWalletCertsHelper
  import Ysc.GoogleWalletCredentialsHelper
  import Ysc.TicketAccessFixtures

  alias Ysc.Tickets.AccessToken
  alias YscWeb.Emails.TicketAccessHelpers

  test "GET /t/:token/apple downloads a pass without signing in", %{conn: conn} do
    %{tickets: [ticket]} = granted_tickets()
    token = AccessToken.sign_ticket(ticket.id)

    with_fake_certs(fn ->
      conn = get(conn, "/t/#{token}/apple")

      assert <<80, 75, _::binary>> = response(conn, 200)

      assert get_resp_header(conn, "content-type") |> hd() =~
               "application/vnd.apple.pkpass"

      assert get_resp_header(conn, "content-disposition") ==
               ["attachment; filename=\"ticket.pkpass\""]
    end)
  end

  test "GET /t/:token/apple still works when some other user is signed in", %{
    conn: conn
  } do
    %{tickets: [ticket]} = granted_tickets()
    token = AccessToken.sign_ticket(ticket.id)
    conn = log_in_user(conn, user_fixture())

    with_fake_certs(fn ->
      conn = get(conn, "/t/#{token}/apple")

      assert <<80, 75, _::binary>> = response(conn, 200)
    end)
  end

  test "ticket email cards point at public /t/:token wallet URLs when configured" do
    %{order: order, tickets: [ticket]} = granted_tickets()
    ticket_id = ticket.id
    order = Ysc.Tickets.get_ticket_order_for_email(order.id)

    with_fake_certs(fn ->
      with_google_wallet_credentials(fn ->
        [card] = TicketAccessHelpers.ticket_cards(order.tickets)

        assert card.apple_wallet_url =~ "/t/"
        assert card.apple_wallet_url =~ "/apple"
        refute card.apple_wallet_url =~ "/wallet/tickets/"

        assert card.google_wallet_url =~ "/t/"
        assert card.google_wallet_url =~ "/google"

        apple_token =
          card.apple_wallet_url
          |> URI.parse()
          |> Map.fetch!(:path)
          |> String.replace_prefix("/t/", "")
          |> String.replace_suffix("/apple", "")

        assert {:ok, ^ticket_id} = AccessToken.verify_ticket(apple_token)
      end)
    end)
  end
end
