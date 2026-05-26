defmodule YscWeb.TicketQrGoogleWalletLiveTest do
  @moduledoc """
  Regression tests for parallel Google Wallet save-URL generation on TicketQrLive (#351).

  Runs with async: false because credential injection mutates global app state.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.TicketsFixtures
  import Ysc.GoogleWalletCredentialsHelper

  test "renders a save link per confirmed ticket after async load", %{conn: conn} do
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

      assert html =~ "pay.google.com/gp/v/save/"

      {:ok, doc} = Floki.parse_fragment(html)

      assert length(Floki.find(doc, "a[href*='pay.google.com/gp/v/save/']")) == 2
    end)
  end
end
