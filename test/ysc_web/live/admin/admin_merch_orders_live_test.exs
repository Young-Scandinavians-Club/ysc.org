defmodule YscWeb.AdminMerchOrdersLiveTest do
  use YscWeb.ConnCase, async: false, mox_global_first: true

  import Mox
  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.MerchFixtures

  alias Ysc.Merch.Orders
  alias Ysc.Printful.{ClientMock, Error}

  setup :verify_on_exit!

  describe "access" do
    test "volunteers are sent back to the admin home", %{conn: conn} do
      volunteer = user_fixture(%{role: "volunteer"})
      conn = log_in_user(conn, volunteer)

      for path <- ["/admin/merch/orders", "/admin/merch/orders/new"] do
        assert {:error, {:redirect, %{to: "/admin"}}} = live(conn, path)
      end
    end

    test "members cannot reach it at all", %{conn: conn} do
      conn = log_in_user(conn, member_fixture())
      assert {:error, {:redirect, _}} = live(conn, "/admin/merch/orders")
    end
  end

  describe "as a full admin" do
    setup %{conn: conn} do
      admin =
        user_fixture(%{role: "admin", first_name: "Lars", last_name: "Nilsson"})

      %{conn: log_in_user(conn, admin), admin: admin}
    end

    test "lists club-paid orders with who they are for", %{
      conn: conn,
      admin: admin
    } do
      order = admin_order_fixture(admin, %{recipient_name: "Bar Staff"})

      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders")

      assert has_element?(
               view,
               "#admin_merch_orders_list-row-#{order.id}",
               order.reference_id
             )

      assert has_element?(
               view,
               "#admin_merch_orders_list-row-#{order.id}",
               "Bar Staff"
             )

      assert has_element?(
               view,
               "#admin_merch_orders_list-row-#{order.id}",
               "Club-paid"
             )

      assert has_element?(view, "#new-club-order")
    end

    test "badges are styled", %{conn: conn, admin: admin} do
      comp = admin_order_fixture(admin)

      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders")

      # A badge with a type the component doesn't know renders with no color.
      assert has_element?(
               view,
               "#admin_merch_orders_list-row-#{comp.id} span.bg-violet-100",
               "Club-paid"
             )

      assert has_element?(
               view,
               "#admin_merch_orders_list-row-#{comp.id} span.bg-sky-100",
               "Sending to printer"
             )
    end

    test "every order status maps to a badge color the component supports" do
      supported = ~w(default sky green yellow red violet dark zinc)

      for status <- Ysc.Merch.Order.statuses() do
        {_label, type} = YscWeb.ShopComponents.status_display(status)
        assert type in supported, "#{status} uses unknown badge type #{type}"
      end
    end

    test "has an empty state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders")
      assert has_element?(view, "#admin_merch_orders_list-empty")
    end

    test "needs attention shows only failed orders, and the tab counts them", %{
      conn: conn,
      admin: admin
    } do
      ok = admin_order_fixture(admin, %{status: :shipped})
      failed = admin_order_fixture(admin, %{status: :failed})

      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders")
      assert has_element?(view, "#merch-attention-count", "1")

      view |> element("#orders-filter-needs_attention") |> render_click()
      assert_patch(view, ~p"/admin/merch/orders?filter=needs_attention")

      assert has_element?(view, "#admin_merch_orders_list-row-#{failed.id}")
      refute has_element?(view, "#admin_merch_orders_list-row-#{ok.id}")
    end

    test "shows how many orders there are", %{conn: conn, admin: admin} do
      for _ <- 1..3, do: admin_order_fixture(admin)

      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders")
      assert has_element?(view, "#orders-count", "3 orders")
    end

    test "search narrows the list and keeps the filter", %{
      conn: conn,
      admin: admin
    } do
      stickers =
        admin_order_fixture(admin, %{
          recipient_name: "Sticker Fan",
          purpose: "Gala"
        })

      other =
        admin_order_fixture(admin, %{
          recipient_name: "Bar Staff",
          purpose: "Happy hour"
        })

      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders")

      view
      |> form("#orders-search-form", %{"q" => "sticker fan"})
      |> render_change()

      assert_patch(view, ~p"/admin/merch/orders?q=sticker+fan")

      assert has_element?(view, "#admin_merch_orders_list-row-#{stickers.id}")
      refute has_element?(view, "#admin_merch_orders_list-row-#{other.id}")
      assert has_element?(view, "#orders-count", "1 order match")
      assert has_element?(view, "#orders-search-input[value='sticker fan']")

      # The chips carry the search with them.
      view |> element("#orders-filter-club_paid") |> render_click()
      assert_patch(view, ~p"/admin/merch/orders?filter=club_paid&q=sticker+fan")
      assert has_element?(view, "#admin_merch_orders_list-row-#{stickers.id}")
    end

    test "search with no match says so, and clearing brings the orders back", %{
      conn: conn,
      admin: admin
    } do
      order = admin_order_fixture(admin)

      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders?q=zzz-nobody")

      assert has_element?(view, "#admin_merch_orders_list-empty", "zzz-nobody")
      refute has_element?(view, "#admin_merch_orders_list-row-#{order.id}")

      view |> element("button[phx-click=clear-search]") |> render_click()
      assert_patch(view, ~p"/admin/merch/orders")
      assert has_element?(view, "#admin_merch_orders_list-row-#{order.id}")
    end

    test "searching by what is in the order", %{conn: conn, admin: admin} do
      variant = Ysc.MerchFixtures.variant_fixture(nil, %{name: "Tomte Sticker"})
      order = admin_order_fixture(admin, %{items: [{variant, 20}]})
      other = admin_order_fixture(admin)

      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders?q=tomte")

      assert has_element?(view, "#admin_merch_orders_list-row-#{order.id}")
      refute has_element?(view, "#admin_merch_orders_list-row-#{other.id}")
    end

    test "long lists are split into pages", %{conn: conn, admin: admin} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      [newest, middle, oldest] =
        for n <- 1..3 do
          admin_order_fixture(admin, %{inserted_at: DateTime.add(now, -n * 60)})
        end

      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders?page_size=2")

      assert has_element?(view, "#admin_merch_orders_list-row-#{newest.id}")
      assert has_element?(view, "#admin_merch_orders_list-row-#{middle.id}")
      refute has_element?(view, "#admin_merch_orders_list-row-#{oldest.id}")
      assert has_element?(view, "#orders-count", "3 orders")
      assert has_element?(view, "a[href*='page=2']")

      {:ok, page2, _html} =
        live(conn, ~p"/admin/merch/orders?page_size=2&page=2")

      assert has_element?(page2, "#admin_merch_orders_list-row-#{oldest.id}")
      refute has_element?(page2, "#admin_merch_orders_list-row-#{newest.id}")
    end

    test "a short list has no pager", %{conn: conn, admin: admin} do
      admin_order_fixture(admin)
      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders")
      refute has_element?(view, "a[href*='page=2']")
    end

    test "a page past the end shows nothing rather than crashing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders?page=50")
      assert has_element?(view, "#admin_merch_orders_list-empty")
    end

    test "garbage in the query string is ignored", %{conn: conn, admin: admin} do
      order = admin_order_fixture(admin)

      {:ok, view, _html} =
        live(conn, ~p"/admin/merch/orders?page=banana&page_size=-1&filter=nope")

      assert has_element?(view, "#orders-filters")

      assert is_boolean(
               has_element?(view, "#admin_merch_orders_list-row-#{order.id}")
             )
    end

    test "an unknown filter falls back to all", %{conn: conn, admin: admin} do
      order = admin_order_fixture(admin)
      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders?filter=bogus")
      assert has_element?(view, "#admin_merch_orders_list-row-#{order.id}")
    end

    test "a row opens the order", %{conn: conn, admin: admin} do
      order = admin_order_fixture(admin)
      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders")

      view
      |> element("#admin_merch_orders_list-row-#{order.id}")
      |> render_click()

      assert_redirect(view, ~p"/admin/merch/orders/#{order.id}")
    end

    test "the products page links here and shows the attention count", %{
      conn: conn,
      admin: admin
    } do
      admin_order_fixture(admin, %{status: :failed})
      {:ok, view, _html} = live(conn, ~p"/admin/merch")
      assert has_element?(view, "#merch-attention-count", "1")
    end
  end

  describe "order detail" do
    setup %{conn: conn} do
      admin =
        user_fixture(%{role: "admin", first_name: "Lars", last_name: "Nilsson"})

      event = Ysc.EventsFixtures.event_fixture()
      %{conn: log_in_user(conn, admin), admin: admin, event: event}
    end

    test "shows a club-paid order: who, why, event and cost", %{
      conn: conn,
      admin: admin,
      event: event
    } do
      order =
        admin_order_fixture(admin, %{
          event_id: event.id,
          purpose: "Happy hour giveaway",
          estimated_cost: Money.new(:USD, "118.40")
        })

      {:ok, view, html} = live(conn, ~p"/admin/merch/orders/#{order.id}")

      assert html =~ "Lars Nilsson"
      assert has_element?(view, "#order-why", "Happy hour giveaway")
      assert has_element?(view, "#order-event-link", event.title)
      assert has_element?(view, "#money-paid", "The club pays")
      assert has_element?(view, "#money-cost", "$118.40")
      assert has_element?(view, "#order-items")
      refute has_element?(view, "#retry-order")
    end

    test "shows a member purchase with a link to the payment", %{conn: conn} do
      member = member_fixture()
      order = purchase_order_fixture(member, :submitted)

      Ysc.Ledgers.ensure_basic_accounts()

      {:ok, {payment, _, _}} =
        Ysc.Ledgers.process_payment(%{
          user_id: member.id,
          amount: order.total_amount,
          entity_type: :merch,
          entity_id: order.id,
          external_payment_id:
            "pi_detail_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(:USD, "1.92"),
          description: "Merch",
          property: nil,
          payment_method_id: nil
        })

      order
      |> Ecto.Changeset.change(payment_id: payment.id)
      |> Ysc.Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders/#{order.id}")

      assert has_element?(view, "#money-paid", "$")
      assert has_element?(view, "#order-payment-link")
      refute has_element?(view, "#order-why")
    end

    test "a failed order explains itself and can be sent again", %{
      conn: conn,
      admin: admin
    } do
      stub(ClientMock, :get_order_by_external_id, fn _ ->
        {:error, %Error{type: :not_found, status: 404, message: "Not found"}}
      end)

      stub(ClientMock, :create_order, fn _, true ->
        {:ok,
         %{"id" => 555, "status" => "pending", "costs" => %{"total" => "20.00"}}}
      end)

      order =
        admin_order_fixture(admin, %{status: :failed})
        |> Ecto.Changeset.change(
          failure_reason: "Printful rejected the order: Bad address"
        )
        |> Ysc.Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders/#{order.id}")

      assert has_element?(view, "#order-failure", "Bad address")
      assert has_element?(view, "#retry-order")

      view |> element("#retry-order") |> render_click()

      assert Orders.get_order!(order.id).status == :submitted
      refute has_element?(view, "#retry-order")
      refute has_element?(view, "#order-failure")
    end

    test "unknown ids go back to the list", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/admin/merch/orders"}}} =
               live(conn, ~p"/admin/merch/orders/#{Ecto.ULID.generate()}")
    end
  end

  describe "on a member's admin page (paging)" do
    test "long lists are paged", %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      member = member_fixture()
      for _ <- 1..3, do: admin_order_fixture(admin, %{user_id: member.id})

      {:ok, view, _html} =
        live(
          log_in_user(conn, admin),
          ~p"/admin/users/#{member.id}/details/merch?page_size=2"
        )

      render_async(view)

      assert has_element?(view, "#user_merch_orders_list tbody tr:nth-child(2)")
      refute has_element?(view, "#user_merch_orders_list tbody tr:nth-child(3)")
      assert has_element?(view, "a[href*='page=2']")
    end
  end

  describe "on a member's admin page" do
    test "lists the merch they received", %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      member = member_fixture()
      order = admin_order_fixture(admin, %{user_id: member.id})

      {:ok, view, _html} =
        live(
          log_in_user(conn, admin),
          ~p"/admin/users/#{member.id}/details/merch"
        )

      render_async(view)

      assert has_element?(
               view,
               "#user_merch_orders_list-row-#{order.id}",
               order.reference_id
             )
    end
  end
end
