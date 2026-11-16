defmodule YscWeb.PublicTicketControllerTest do
  use YscWeb.ConnCase, async: true

  import Ysc.EventsFixtures
  import Ysc.TicketAccessFixtures

  alias Ysc.Tickets.AccessToken

  describe "GET /t/:token/qr.png" do
    test "serves a PNG for a valid ticket token without signing in", %{
      conn: conn
    } do
      %{tickets: [ticket]} = granted_tickets()

      conn = get(conn, "/t/#{AccessToken.sign_ticket(ticket.id)}/qr.png")

      assert response(conn, 200) =~ "PNG"
      assert get_resp_header(conn, "content-type") |> hd() =~ "image/png"

      assert get_resp_header(conn, "cache-control") == [
               "private, max-age=86400"
             ]
    end

    test "works for image proxies that only accept images", %{conn: conn} do
      %{tickets: [ticket]} = granted_tickets()

      conn =
        conn
        |> put_req_header("accept", "image/webp")
        |> get("/t/#{AccessToken.sign_ticket(ticket.id)}/qr.png")

      assert response(conn, 200)
    end

    test "404s on a bad token", %{conn: conn} do
      assert conn |> get("/t/not-a-token/qr.png") |> response(404)
    end

    test "404s on an order-wide token, which doesn't identify one ticket", %{
      conn: conn
    } do
      %{order: order} = granted_tickets()

      assert conn
             |> get("/t/#{AccessToken.sign_order(order.id)}/qr.png")
             |> response(404)
    end

    test "404s on a multi-ticket token, which doesn't identify one ticket", %{
      conn: conn
    } do
      %{tickets: tickets} = granted_tickets(2)
      token = AccessToken.sign_tickets(Enum.map(tickets, & &1.id))

      assert conn |> get("/t/#{token}/qr.png") |> response(404)
    end

    test "404s once the ticket is no longer confirmed", %{conn: conn} do
      %{tickets: [ticket]} = granted_tickets()

      ticket
      |> Ecto.Changeset.change(status: :cancelled)
      |> Ysc.Repo.update!()

      assert conn
             |> get("/t/#{AccessToken.sign_ticket(ticket.id)}/qr.png")
             |> response(404)
    end
  end

  describe "wallet downloads" do
    test "404 on a bad token", %{conn: conn} do
      assert conn |> get("/t/nope/apple") |> response(404)
      assert conn |> get("/t/nope/google") |> response(404)
    end

    test "404 when the wallet isn't configured", %{conn: conn} do
      %{tickets: [ticket]} = granted_tickets()
      token = AccessToken.sign_ticket(ticket.id)

      assert conn |> get("/t/#{token}/apple") |> response(404)
      assert conn |> get("/t/#{token}/google") |> response(404)
    end

    test "does not query tickets when the wallet isn't configured", %{
      conn: conn
    } do
      %{tickets: [ticket]} = granted_tickets()
      token = AccessToken.sign_ticket(ticket.id)

      {_result, ticket_queries} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            get(conn, "/t/#{token}/apple")
            get(conn, "/t/#{token}/google")
          end,
          pattern: ~r/FROM "tickets"/i,
          caller_pids: [self()]
        )

      assert ticket_queries == 0
    end

    test "404 on an order-wide token, which doesn't identify one ticket", %{
      conn: conn
    } do
      %{order: order} = granted_tickets()
      token = AccessToken.sign_order(order.id)

      assert conn |> get("/t/#{token}/apple") |> response(404)
      assert conn |> get("/t/#{token}/google") |> response(404)
    end

    test "404 on a multi-ticket token, which doesn't identify one ticket", %{
      conn: conn
    } do
      %{tickets: tickets} = granted_tickets(2)
      token = AccessToken.sign_tickets(Enum.map(tickets, & &1.id))

      assert conn |> get("/t/#{token}/apple") |> response(404)
      assert conn |> get("/t/#{token}/google") |> response(404)
    end

    test "404 once the ticket is no longer confirmed", %{conn: conn} do
      %{tickets: [ticket]} = granted_tickets()

      ticket
      |> Ecto.Changeset.change(status: :cancelled)
      |> Ysc.Repo.update!()

      token = AccessToken.sign_ticket(ticket.id)

      assert conn |> get("/t/#{token}/apple") |> response(404)
      assert conn |> get("/t/#{token}/google") |> response(404)
    end

    test "404 on a donation ticket, which cannot be scanned at the door", %{
      conn: conn
    } do
      %{user: user, event: event} = granted_tickets()
      tier = ticket_tier_fixture(%{event_id: event.id, type: :donation})

      donation =
        %Ysc.Events.Ticket{
          id: Ecto.ULID.generate(),
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: tier.id,
          status: :confirmed,
          expires_at:
            DateTime.add(DateTime.utc_now(), 1, :day)
            |> DateTime.truncate(:second)
        }
        |> Ysc.Repo.insert!()

      token = AccessToken.sign_ticket(donation.id)

      assert conn |> get("/t/#{token}/qr.png") |> response(404)
      assert conn |> get("/t/#{token}/apple") |> response(404)
      assert conn |> get("/t/#{token}/google") |> response(404)
    end
  end
end
