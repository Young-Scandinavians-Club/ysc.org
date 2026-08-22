defmodule YscWeb.AdminTicketPurchasesLiveTest do
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Events.Ticket
  alias Ysc.Repo

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

  defp insert_confirmed_ticket(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %Ticket{
      id: Ecto.ULID.generate(),
      event_id: attrs.event_id,
      ticket_tier_id: attrs.ticket_tier_id,
      user_id: attrs.user_id,
      status: :confirmed,
      inserted_at: Map.get(attrs, :inserted_at, now),
      expires_at: DateTime.add(now, 1, :day)
    }
    |> Repo.insert!()
  end

  defp purchase_row_ids(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("tr")
    |> Enum.flat_map(&LazyHTML.attribute(&1, "id"))
    |> Enum.filter(&String.starts_with?(&1, "ticket-purchase-"))
  end

  describe "ticket purchases table" do
    setup [:create_admin]

    test "defaults to newest purchase first and shows the purchase date", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id, state: :published})

      ga =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "GA Table",
          quantity: 50
        })

      alice =
        user_fixture(%{
          first_name: "Alice",
          last_name: "Anderson",
          email: "alice-purchases-#{System.unique_integer()}@example.com"
        })

      zane =
        user_fixture(%{
          first_name: "Zane",
          last_name: "Zulu",
          email: "zane-purchases-#{System.unique_integer()}@example.com"
        })

      insert_confirmed_ticket(%{
        event_id: event.id,
        ticket_tier_id: ga.id,
        user_id: alice.id,
        inserted_at: ~U[2026-08-01 18:30:00Z]
      })

      insert_confirmed_ticket(%{
        event_id: event.id,
        ticket_tier_id: ga.id,
        user_id: zane.id,
        inserted_at: ~U[2026-08-10 18:30:00Z]
      })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      assert has_element?(view, "#ticket-purchases-sort-purchased_at")

      assert has_element?(
               view,
               "#ticket-purchase-#{alice.id}",
               "Alice Anderson"
             )

      assert has_element?(view, "#ticket-purchase-#{zane.id}", "Zane Zulu")
      # 18:30 UTC on 1 Aug is 11:30am Pacific (PDT).
      assert has_element?(
               view,
               "#ticket-purchase-#{alice.id}",
               "Aug 1, 2026 at 11:30am"
             )

      assert purchase_row_ids(render(view)) == [
               "ticket-purchase-#{zane.id}",
               "ticket-purchase-#{alice.id}"
             ]
    end

    test "sorts by purchaser name, toggling direction on repeat click", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id, state: :published})

      ga =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "GA Sort",
          quantity: 50
        })

      alice =
        user_fixture(%{
          first_name: "Alice",
          last_name: "Anderson",
          email: "alice-sort-#{System.unique_integer()}@example.com"
        })

      zane =
        user_fixture(%{
          first_name: "Zane",
          last_name: "Zulu",
          email: "zane-sort-#{System.unique_integer()}@example.com"
        })

      insert_confirmed_ticket(%{
        event_id: event.id,
        ticket_tier_id: ga.id,
        user_id: alice.id,
        inserted_at: ~U[2026-08-10 10:00:00Z]
      })

      insert_confirmed_ticket(%{
        event_id: event.id,
        ticket_tier_id: ga.id,
        user_id: zane.id,
        inserted_at: ~U[2026-08-01 10:00:00Z]
      })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      view |> element("#ticket-purchases-sort-user_name") |> render_click()

      assert purchase_row_ids(render(view)) == [
               "ticket-purchase-#{alice.id}",
               "ticket-purchase-#{zane.id}"
             ]

      view |> element("#ticket-purchases-sort-user_name") |> render_click()

      assert purchase_row_ids(render(view)) == [
               "ticket-purchase-#{zane.id}",
               "ticket-purchase-#{alice.id}"
             ]
    end

    test "sorts by quantity descending first, then toggles to ascending", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id, state: :published})

      ga =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "GA Qty",
          quantity: 50
        })

      one =
        user_fixture(%{
          first_name: "One",
          last_name: "Ticket",
          email: "one-qty-#{System.unique_integer()}@example.com"
        })

      three =
        user_fixture(%{
          first_name: "Three",
          last_name: "Tickets",
          email: "three-qty-#{System.unique_integer()}@example.com"
        })

      insert_confirmed_ticket(%{
        event_id: event.id,
        ticket_tier_id: ga.id,
        user_id: one.id
      })

      for _i <- 1..3 do
        insert_confirmed_ticket(%{
          event_id: event.id,
          ticket_tier_id: ga.id,
          user_id: three.id
        })
      end

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      view |> element("#ticket-purchases-sort-ticket_count") |> render_click()

      assert purchase_row_ids(render(view)) == [
               "ticket-purchase-#{three.id}",
               "ticket-purchase-#{one.id}"
             ]

      view |> element("#ticket-purchases-sort-ticket_count") |> render_click()

      assert purchase_row_ids(render(view)) == [
               "ticket-purchase-#{one.id}",
               "ticket-purchase-#{three.id}"
             ]
    end

    test "sorts nameless purchaser rows without crashing", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id, state: :published})

      ga =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "GA Orphan",
          quantity: 50
        })

      named =
        user_fixture(%{
          first_name: "Named",
          last_name: "Buyer",
          email: "named-buyer-#{System.unique_integer()}@example.com"
        })

      insert_confirmed_ticket(%{
        event_id: event.id,
        ticket_tier_id: ga.id,
        user_id: named.id
      })

      insert_confirmed_ticket(%{
        event_id: event.id,
        ticket_tier_id: ga.id,
        user_id: nil
      })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      assert has_element?(view, "#ticket-purchase-#{named.id}")
      assert has_element?(view, "#ticket-purchase-")

      html =
        view
        |> element("#ticket-purchases-sort-user_name")
        |> render_click()

      ids = purchase_row_ids(html)
      assert "ticket-purchase-" in ids
      assert "ticket-purchase-#{named.id}" in ids
    end

    test "CSV export includes Purchase Date in Pacific time", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id, state: :published})

      ga =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "GA CSV",
          quantity: 50
        })

      buyer =
        user_fixture(%{
          first_name: "Csv",
          last_name: "Buyer",
          email: "csv-buyer-#{System.unique_integer()}@example.com"
        })

      insert_confirmed_ticket(%{
        event_id: event.id,
        ticket_tier_id: ga.id,
        user_id: buyer.id,
        inserted_at: ~U[2026-08-01 18:30:00Z]
      })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      view |> element("#export-tickets-csv") |> render_click()

      assert_push_event(view, "download-csv", %{content: b64, filename: fname})
      assert fname =~ "tickets_export_"

      csv = Base.decode64!(b64)
      assert csv =~ "Purchase Date"
      assert csv =~ "Aug 1, 2026 at 11:30am"
      assert csv =~ buyer.email
    end
  end
end
