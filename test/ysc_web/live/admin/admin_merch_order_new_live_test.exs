defmodule YscWeb.AdminMerchOrderNewLiveTest do
  use YscWeb.ConnCase, async: false, mox_global_first: true

  import Mox
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import Ysc.AccountsFixtures
  import Ysc.MerchFixtures

  alias Ysc.Merch.{Order, Orders}
  alias Ysc.Printful.{ClientMock, Error}
  alias Ysc.Repo

  setup :verify_on_exit!

  setup %{conn: conn} do
    admin =
      user_fixture(%{role: "admin", first_name: "Lars", last_name: "Nilsson"})

    tee =
      variant_fixture(nil, %{
        name: "Club Tee / Black / M",
        retail_price: Money.new(:USD, "25")
      })

    event = Ysc.EventsFixtures.event_fixture()

    %{conn: log_in_user(conn, admin), admin: admin, tee: tee, event: event}
  end

  defp stub_quote(estimate \\ "118.40") do
    stub(ClientMock, :shipping_rates, fn _, _ ->
      {:ok,
       [
         %{
           "id" => "EXPRESS",
           "name" => "Express",
           "rate" => "14.50",
           "currency" => "USD",
           "minDeliveryDays" => 1,
           "maxDeliveryDays" => 2
         },
         %{
           "id" => "STANDARD",
           "name" => "Flat Rate",
           "rate" => "5.95",
           "currency" => "USD",
           "minDeliveryDays" => 3,
           "maxDeliveryDays" => 5
         }
       ]}
    end)

    stub(ClientMock, :estimate_costs, fn payload ->
      total = if payload.shipping == "EXPRESS", do: "130.00", else: estimate

      {:ok,
       %{
         "costs" => %{
           "calculation_status" => "done",
           "shipping" => "5.95",
           "total" => total
         }
       }}
    end)
  end

  defp stub_printful_accepts do
    stub(ClientMock, :get_order_by_external_id, fn _ ->
      {:error, %Error{type: :not_found, status: 404, message: "Not found"}}
    end)

    stub(ClientMock, :create_order, fn payload, true ->
      send(self(), {:printful_payload, payload})

      {:ok,
       %{"id" => 4242, "status" => "pending", "costs" => %{"total" => "118.40"}}}
    end)
  end

  defp custom_params(tee, overrides \\ %{}) do
    Map.merge(
      %{
        "recipient" => "custom",
        "name" => "Bar Staff",
        "address1" => "1 Market St",
        "address2" => "",
        "city" => "San Francisco",
        "state_code" => "CA",
        "zip" => "94105",
        "phone" => "",
        "email" => "bar@example.com",
        "purpose" => "Happy hour giveaway",
        "event_id" => "",
        "lines" => %{"0" => %{"variant_id" => tee.id, "quantity" => "5"}}
      },
      overrides
    )
  end

  # Picking who it is for reveals the address fields.
  defp choose(view, kind) do
    view
    |> form("#merch-order-form")
    |> render_change(%{"order" => %{"recipient" => kind}})
  end

  defp fill(view, params) do
    view |> form("#merch-order-form", order: params) |> render_change()
  end

  defp review(view, params) do
    if params["recipient"] != "member", do: choose(view, params["recipient"])
    fill(view, params)
    view |> form("#merch-order-form", order: params) |> render_submit()
    render_async(view)
  end

  describe "the details step" do
    test "starts with the recipient choice and one empty item", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders/new")

      assert has_element?(view, "#recipient-member[checked]")
      assert has_element?(view, "#merch-order-member")
      assert has_element?(view, "#order-line-0")
      # The address appears once there is someone to ship to.
      refute has_element?(view, "#order-address")
      assert has_element?(view, "#review-order")
    end

    test "choosing a member fills in their address", %{conn: conn} do
      member = member_fixture(%{first_name: "Astrid", last_name: "Berg"})
      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders/new")

      render_hook(view, "select-user", %{"id" => member.id})

      assert has_element?(view, "#order-address")

      assert has_element?(
               view,
               "input[name='order[name]'][value='Astrid Berg']"
             )

      assert has_element?(
               view,
               "input[name='order[email]'][value='#{member.email}']"
             )
    end

    test "Me fills in the admin's own details", %{conn: conn, admin: admin} do
      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders/new")

      choose(view, "self")

      assert has_element?(
               view,
               "input[name='order[name]'][value='Lars Nilsson']"
             )

      assert has_element?(
               view,
               "input[name='order[email]'][value='#{admin.email}']"
             )
    end

    test "Someone else starts with a blank address", %{conn: conn} do
      member = member_fixture(%{first_name: "Astrid", last_name: "Berg"})
      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders/new")
      render_hook(view, "select-user", %{"id" => member.id})

      choose(view, "custom")

      assert has_element?(view, "#order-address")

      refute has_element?(
               view,
               "input[name='order[name]'][value='Astrid Berg']"
             )
    end

    test "items can be added and removed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders/new")

      refute has_element?(view, "#remove-line-0")

      view |> element("#add-line") |> render_click()
      assert has_element?(view, "#order-line-1")
      assert has_element?(view, "#remove-line-0")

      view |> element("#remove-line-0") |> render_click()
      refute has_element?(view, "#order-line-0")
      assert has_element?(view, "#order-line-1")
      refute has_element?(view, "#remove-line-1")
    end

    test "incomplete details show what is missing and go nowhere", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders/new")

      choose(view, "custom")

      view |> form("#merch-order-form") |> render_submit()

      assert has_element?(view, "#merch-order-form")
      assert has_element?(view, "#lines-error", "Add at least one item")
      refute has_element?(view, "#merch-order-review")
      assert render(view) =~ "Say why the club is paying"
    end

    # The browser flags fields the admin has not touched with `_unused_*`
    # keys, and Phoenix hides errors on "unused" fields. Pressing Review has
    # to show every problem regardless.
    test "problems show even for fields that were never touched", %{
      conn: conn,
      tee: tee
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders/new")
      choose(view, "custom")

      untouched =
        custom_params(tee, %{"purpose" => ""})
        |> Map.merge(%{"_unused_purpose" => "", "_unused_zip" => ""})

      render_submit(view, "review", %{"order" => untouched})

      assert has_element?(view, "#merch-order-form")
      refute has_element?(view, "#merch-order-review")
      # Beside the field...
      assert has_element?(view, "#order-why", "Say why the club is paying")
      # ...and next to the button that was pressed.
      assert has_element?(
               view,
               "#order-problems li",
               "Say why the club is paying"
             )
    end

    test "the problem list lists everything wrong, and updates as it is fixed",
         %{
           conn: conn,
           tee: tee
         } do
      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders/new")
      choose(view, "custom")

      render_submit(view, "review", %{
        "order" => %{
          "recipient" => "custom",
          "name" => "",
          "zip" => "123",
          "purpose" => "",
          "lines" => %{"0" => %{"variant_id" => "", "quantity" => "1"}}
        }
      })

      assert has_element?(view, "#order-problems li", "Name can't be blank")

      assert has_element?(
               view,
               "#order-problems li",
               "ZIP code must be a 5-digit"
             )

      assert has_element?(view, "#order-problems li", "Add at least one item")

      assert has_element?(
               view,
               "#order-problems li",
               "Say why the club is paying"
             )

      render_change(view, "validate", %{
        "order" => %{"purpose" => "Giveaway", "_unused_name" => ""}
      })

      refute has_element?(
               view,
               "#order-problems li",
               "Say why the club is paying"
             )

      assert has_element?(view, "#order-problems li", "Name can't be blank")

      fill(view, custom_params(tee))

      refute has_element?(view, "#order-problems")
    end

    test "nothing is flagged before Review is pressed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders/new")
      choose(view, "custom")

      render_change(view, "validate", %{
        "order" => %{"purpose" => "", "_unused_purpose" => ""}
      })

      refute has_element?(view, "#order-problems")
    end

    test "a member recipient must be chosen", %{conn: conn, tee: tee} do
      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders/new")

      view
      |> form("#merch-order-form",
        order: %{
          "purpose" => "Gift",
          "lines" => %{"0" => %{"variant_id" => tee.id, "quantity" => "1"}}
        }
      )
      |> render_submit()

      assert has_element?(view, "#merch-order-form")
      assert render(view) =~ "Choose the member"
    end
  end

  describe "review and placing" do
    test "shows Printful's shipping and the cost to the club", %{
      conn: conn,
      tee: tee
    } do
      stub_quote()
      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders/new")

      review(view, custom_params(tee))

      assert has_element?(view, "#merch-order-review")
      assert has_element?(view, "#review-address", "Bar Staff")
      assert has_element?(view, "#review-items", "5 × Club Tee / Black / M")
      assert has_element?(view, "#review-purpose", "Happy hour giveaway")
      assert has_element?(view, "#estimate-total", "$118.40")
      # Cheapest option first.
      assert has_element?(
               view,
               "#shipping-option option[selected]",
               "Flat Rate"
             )
    end

    test "changing the shipping option re-prices", %{conn: conn, tee: tee} do
      stub_quote()
      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders/new")
      review(view, custom_params(tee))

      view
      |> form("#shipping-form", %{"shipping" => "EXPRESS"})
      |> render_change()

      render_async(view)

      assert has_element?(view, "#estimate-total", "$130.00")
    end

    test "placing the order sends it, tells the board and opens the order", %{
      conn: conn,
      admin: admin,
      tee: tee,
      event: event
    } do
      stub_quote()
      stub_printful_accepts()
      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders/new")

      review(view, custom_params(tee, %{"event_id" => event.id}))
      view |> element("#place-order") |> render_click()

      order = Repo.one!(Order)
      assert_redirect(view, ~p"/admin/merch/orders/#{order.id}")

      order = Orders.get_order!(order.id)
      assert order.kind == :admin_comp
      assert order.granted_by_id == admin.id
      assert order.event_id == event.id
      assert order.shipping_method == "STANDARD"
      assert order.status == :submitted
      assert Money.equal?(order.estimated_cost, Money.new(:USD, "118.40"))
      assert is_nil(order.user_id)

      assert order.printful_order_id == 4242

      assert_email_sent(
        subject: "We've got your merch order (#{order.reference_id})"
      )

      assert_email_sent(
        subject:
          "Lars Nilsson placed a club-paid merch order (#{order.reference_id})"
      )
    end

    test "ordering for a member makes them the recipient", %{
      conn: conn,
      tee: tee
    } do
      stub_quote()
      stub_printful_accepts()
      member = member_fixture()
      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders/new")

      render_hook(view, "select-user", %{"id" => member.id})

      review(
        view,
        custom_params(tee, %{
          "recipient" => "member",
          "name" => "Member Name",
          "email" => member.email
        })
      )

      view |> element("#place-order") |> render_click()

      assert Repo.one!(Order).user_id == member.id
    end

    test "Me orders to the admin", %{conn: conn, admin: admin, tee: tee} do
      stub_quote()
      stub_printful_accepts()
      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders/new")

      choose(view, "self")

      review(view, custom_params(tee, %{"recipient" => "self"}))
      view |> element("#place-order") |> render_click()

      assert Repo.one!(Order).user_id == admin.id
    end

    test "can go back and edit", %{conn: conn, tee: tee} do
      stub_quote()
      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders/new")
      review(view, custom_params(tee))

      view |> element("#back-to-details") |> render_click()

      assert has_element?(view, "#merch-order-form")
      assert has_element?(view, "input[name='order[name]'][value='Bar Staff']")
      assert Repo.aggregate(Order, :count) == 0
    end

    test "a price Printful can't give does not stop the order", %{
      conn: conn,
      tee: tee
    } do
      stub_quote()

      stub(ClientMock, :estimate_costs, fn _ ->
        {:error, %Error{type: :server, status: 500, message: "down"}}
      end)

      stub_printful_accepts()
      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders/new")

      review(view, custom_params(tee))
      assert has_element?(view, "#estimate-unavailable")

      view |> element("#place-order") |> render_click()
      assert is_nil(Repo.one!(Order).estimated_cost)
    end

    test "Printful refusing the address sends them back to fix it", %{
      conn: conn,
      tee: tee
    } do
      stub(ClientMock, :shipping_rates, fn _, _ ->
        {:error,
         %Error{
           type: :invalid,
           status: 400,
           message: "Zip code does not match state"
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders/new")
      review(view, custom_params(tee))

      assert has_element?(view, "#merch-order-form")
      refute has_element?(view, "#merch-order-review")
      assert Repo.aggregate(Order, :count) == 0
    end

    test "a Printful outage offers a retry", %{conn: conn, tee: tee} do
      stub(ClientMock, :shipping_rates, fn _, _ ->
        {:error, %Error{type: :server, status: 503, message: "down"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders/new")
      review(view, custom_params(tee))

      assert has_element?(view, "#review-error", "couldn't quote shipping")
      assert has_element?(view, "#place-order[disabled]")

      stub_quote()
      view |> element("#retry-review") |> render_click()
      render_async(view)

      assert has_element?(view, "#estimate-total")
    end
  end
end
