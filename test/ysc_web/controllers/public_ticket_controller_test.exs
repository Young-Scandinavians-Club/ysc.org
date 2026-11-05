defmodule YscWeb.PublicTicketControllerTest do
  use YscWeb.ConnCase, async: true

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
  end
end
