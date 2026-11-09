defmodule YscWeb.PublicTicketLiveTest do
  @moduledoc """
  `/t/:token` opens tickets from an email with no login. Runs with
  async: false because the wallet test injects credentials into global app state.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.GoogleWalletCredentialsHelper
  import Ysc.TicketAccessFixtures

  alias Ysc.Tickets.AccessToken

  test "shows every ticket in an order to someone who isn't signed in", %{
    conn: conn
  } do
    %{order: order, tickets: tickets} = granted_tickets(2)

    {:ok, view, _html} = live(conn, ~p"/t/#{AccessToken.sign_order(order.id)}")
    html = render_async(view)

    assert has_element?(view, "#ticket-slider")
    refute html =~ "Scan to check in"

    for ticket <- tickets do
      assert has_element?(view, "#ticket-qr-#{ticket.reference_id}")

      assert has_element?(
               view,
               "#ticket-qr-check-in-hint-#{ticket.reference_id}",
               "Show this to staff"
             )
    end

    refute has_element?(view, "#back-link")
    refute has_element?(view, "#all-orders-link")
    refute has_element?(view, "#confirmation-link")
  end

  test "a guest token shows only the tickets it covers", %{conn: conn} do
    %{tickets: [mine, other]} = granted_tickets(2)

    {:ok, view, _html} = live(conn, ~p"/t/#{AccessToken.sign_ticket(mine.id)}")
    render_async(view)

    assert has_element?(view, "#ticket-qr-#{mine.reference_id}")
    refute has_element?(view, "#ticket-qr-#{other.reference_id}")
  end

  test "a guest multi-ticket token shows only the tickets it covers", %{
    conn: conn
  } do
    %{tickets: [mine, also_mine, other]} = granted_tickets(3)
    token = AccessToken.sign_tickets([mine.id, also_mine.id])

    {:ok, view, _html} = live(conn, ~p"/t/#{token}")
    render_async(view)

    assert has_element?(view, "#ticket-qr-#{mine.reference_id}")
    assert has_element?(view, "#ticket-qr-#{also_mine.reference_id}")
    refute has_element?(view, "#ticket-qr-#{other.reference_id}")
  end

  test "an invalid token says so instead of redirecting to login", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/t/not-a-valid-token")
    render_async(view)

    assert has_element?(view, "#public-ticket-error")
    refute has_element?(view, "#ticket-slider")
  end

  test "cancelled tickets can't be opened", %{conn: conn} do
    %{order: order, tickets: tickets} = granted_tickets(1)

    Enum.each(tickets, fn ticket ->
      ticket |> Ecto.Changeset.change(status: :cancelled) |> Ysc.Repo.update!()
    end)

    {:ok, view, _html} = live(conn, ~p"/t/#{AccessToken.sign_order(order.id)}")
    render_async(view)

    assert has_element?(view, "#public-ticket-error")
    refute has_element?(view, "#ticket-slider")
  end

  test "offers Google Wallet save links per ticket without signing in", %{
    conn: conn
  } do
    %{order: order} = granted_tickets(2)

    with_google_wallet_credentials(fn ->
      {:ok, view, _html} =
        live(conn, ~p"/t/#{AccessToken.sign_order(order.id)}")

      html = render_async(view)
      {:ok, doc} = Floki.parse_fragment(html)

      assert length(Floki.find(doc, "a[href*='pay.google.com/gp/v/save/']")) ==
               2
    end)
  end

  test "Google Wallet link from an email redirects to the save page", %{
    conn: conn
  } do
    %{tickets: [ticket]} = granted_tickets(1)

    with_google_wallet_credentials(fn ->
      conn = get(conn, "/t/#{AccessToken.sign_ticket(ticket.id)}/google")

      assert redirected_to(conn) =~ "https://pay.google.com/gp/v/save/"
    end)
  end
end
