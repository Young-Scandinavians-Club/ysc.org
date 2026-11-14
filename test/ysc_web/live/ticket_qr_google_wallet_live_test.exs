defmodule YscWeb.TicketQrGoogleWalletLiveTest do
  @moduledoc """
  Ticket QR pages link to on-demand Google Wallet redirects instead of
  precomputing save-URL JWTs during load.

  Runs with async: false because credential injection mutates global app state.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.TicketsFixtures
  import Ysc.GoogleWalletCredentialsHelper

  test "renders an on-demand save link per confirmed ticket after async load",
       %{
         conn: conn
       } do
    Ysc.Ledgers.ensure_basic_accounts()

    member =
      user_fixture()
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Ysc.Repo.update!()
      |> Ysc.Repo.reload!()

    event = event_fixture()
    tier = ticket_tier_fixture(%{event_id: event.id})

    order =
      ticket_order_fixture(%{
        user: member,
        event: event,
        ticket_selections: %{tier.id => 2}
      })

    loaded =
      Ysc.Repo.get!(Ysc.Tickets.TicketOrder, order.id)
      |> Ysc.Repo.preload([:tickets])

    Enum.each(loaded.tickets, fn ticket ->
      ticket |> Ecto.Changeset.change(status: :confirmed) |> Ysc.Repo.update!()
    end)

    with_google_wallet_credentials(fn ->
      conn = log_in_user(conn, member)
      {:ok, view, _html} = live(conn, ~p"/tickets/#{order.id}/qr")
      html = render_async(view)

      refute html =~ "pay.google.com"

      {:ok, doc} = Floki.parse_fragment(html)

      hrefs =
        doc
        |> Floki.find("a[href*='/wallet/tickets/'][href$='/google']")
        |> Floki.attribute("href")

      assert length(hrefs) == 2

      for ticket <- loaded.tickets do
        assert Enum.any?(
                 hrefs,
                 &String.ends_with?(
                   &1,
                   "/wallet/tickets/#{ticket.id}/google"
                 )
               )
      end

      {redirect_conn, ticket_queries} =
        Ysc.QueryCounter.with_query_counter(
          fn -> get(conn, hd(hrefs)) end,
          pattern: ~r/FROM "tickets"/i,
          caller_pids: [self()]
        )

      assert redirected_to(redirect_conn) =~
               "https://pay.google.com/gp/v/save/"

      assert ticket_queries == 1
    end)
  end
end
