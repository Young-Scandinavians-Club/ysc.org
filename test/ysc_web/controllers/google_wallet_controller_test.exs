defmodule YscWeb.GoogleWalletControllerTest do
  use YscWeb.ConnCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.TicketsFixtures

  defp member_with_confirmed_ticket do
    Ysc.Ledgers.ensure_basic_accounts()

    user =
      user_fixture()
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Ysc.Repo.update!()
      |> Ysc.Repo.reload!()

    event = event_fixture()
    order = ticket_order_fixture(%{user: user, event: event})

    ticket =
      Ysc.Repo.get!(Ysc.Tickets.TicketOrder, order.id)
      |> Ysc.Repo.preload([:tickets])
      |> Map.fetch!(:tickets)
      |> hd()
      |> Ecto.Changeset.change(status: :confirmed)
      |> Ysc.Repo.update!()

    {user, ticket}
  end

  describe "GET /wallet/tickets/:ticket_id/google" do
    test "redirects unauthenticated users to the login page", %{conn: conn} do
      conn = get(conn, ~p"/wallet/tickets/some-id/google")

      assert redirected_to(conn) =~ "/users/log"
    end

    test "returns 404 when Google Wallet is not configured", %{conn: conn} do
      {user, ticket} = member_with_confirmed_ticket()
      conn = log_in_user(conn, user)

      conn = get(conn, ~p"/wallet/tickets/#{ticket.id}/google")

      assert response(conn, 404)
    end

    test "returns 404 when ticket does not belong to the current user", %{
      conn: conn
    } do
      {_owner, ticket} = member_with_confirmed_ticket()
      other_user = user_fixture()
      conn = log_in_user(conn, other_user)

      conn = get(conn, ~p"/wallet/tickets/#{ticket.id}/google")

      assert response(conn, 404)
    end

    test "returns 404 for a completely non-existent ticket ID", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      conn = get(conn, ~p"/wallet/tickets/#{Ecto.ULID.generate()}/google")

      assert response(conn, 404)
    end
  end
end
