defmodule Ysc.Merch.PrintfulEventsTest do
  # Notification jobs run inline, which sends real (test-adapter) email and
  # records SMS, so this module shares global state with other mail tests.
  use Ysc.DataCase, async: false

  import Swoosh.TestAssertions
  import Ysc.AccountsFixtures
  import Ysc.MerchFixtures

  alias Ysc.Merch.{Order, Orders, PrintfulEvents, Shipment}
  alias Ysc.Messages.MessageIdempotency

  setup do
    member =
      member_fixture(%{phone_number: unique_user_phone()})
      |> Ecto.Changeset.change(
        phone_verified_at: DateTime.truncate(DateTime.utc_now(), :second),
        account_notifications_sms: true
      )
      |> Repo.update!()

    %{member: member, order: purchase_order_fixture(member, :submitted)}
  end

  defp handle(type, order, data \\ %{}, order_fields \\ %{}) do
    payload = printful_event(type, order, data, order_fields)
    PrintfulEvents.handle_event(payload["type"], payload["data"])
  end

  defp status(order), do: Orders.get_order!(order.id).status

  defp shipments(order),
    do: Repo.all(from(s in Shipment, where: s.order_id == ^order.id))

  defp sms_messages do
    MessageIdempotency |> Repo.all() |> Enum.filter(&(&1.message_type == :sms))
  end

  describe "package_shipped" do
    test "records the shipment, ships the order and tells the member by email and text",
         %{order: order, member: member} do
      shipment = printful_shipment()
      assert :ok = handle("package_shipped", order, %{"shipment" => shipment})

      assert status(order) == :shipped
      assert [%Shipment{} = recorded] = shipments(order)
      assert recorded.printful_shipment_id == shipment["id"]
      assert recorded.carrier == "USPS"
      assert recorded.tracking_number == shipment["tracking_number"]
      assert recorded.status == :shipped
      assert recorded.notified_at

      assert_email_sent(
        subject: "Your order is on its way (#{order.reference_id})",
        to: {"", member.email}
      )

      assert [%MessageIdempotency{rendered_message: body}] = sms_messages()
      assert body =~ order.reference_id
      assert body =~ "shipped"
      assert body =~ "USPS"
    end

    test "a shipment id that belongs to another order is ignored", %{
      order: order,
      member: member
    } do
      other = purchase_order_fixture(member, :submitted)
      shipment = printful_shipment()

      assert :ok = handle("package_shipped", order, %{"shipment" => shipment})

      handle("package_shipped", other, %{
        "shipment" => Map.put(shipment, "tracking_number", "STOLEN")
      })

      assert [%Shipment{tracking_number: tracking}] = shipments(order)
      assert tracking == shipment["tracking_number"]
      assert shipments(other) == []
      assert Repo.aggregate(Shipment, :count) == 1
    end

    test "a duplicate event does not notify twice", %{order: order} do
      payload = %{"shipment" => printful_shipment()}

      handle("package_shipped", order, payload)
      assert_email_sent(subject: ~r/on its way/)

      handle("package_shipped", order, payload)
      handle("package_shipped", order, payload)

      refute_email_sent()
      assert length(shipments(order)) == 1
      assert length(sms_messages()) == 1
    end

    test "each parcel of a split order notifies once", %{order: order} do
      handle("package_shipped", order, %{"shipment" => printful_shipment()})
      handle("package_shipped", order, %{"shipment" => printful_shipment()})

      assert length(shipments(order)) == 2
      assert_email_sent(subject: ~r/on its way/)
      assert_email_sent(subject: ~r/on its way/)
    end

    test "arrives before our own submission response was recorded", %{
      member: member
    } do
      order = purchase_order_fixture(member, :submitting)
      assert order.printful_order_id == nil

      payload =
        printful_event(
          "package_shipped",
          %{order | printful_order_id: 777_001},
          %{"shipment" => printful_shipment()}
        )

      assert :ok = PrintfulEvents.handle_event(payload["type"], payload["data"])

      reloaded = Orders.get_order!(order.id)
      assert reloaded.status == :shipped
      assert reloaded.printful_order_id == 777_001
    end

    test "a payload without a usable shipment is ignored", %{order: order} do
      assert :ok = handle("package_shipped", order, %{})

      assert :ok =
               handle("package_shipped", order, %{
                 "shipment" => %{"carrier" => "USPS"}
               })

      assert shipments(order) == []
      assert status(order) == :submitted
      refute_email_sent()
    end

    test "never ships an order that already failed or was canceled", %{
      member: member
    } do
      for status <- [:failed, :canceled] do
        order = purchase_order_fixture(member, status)
        handle("package_shipped", order, %{"shipment" => printful_shipment()})
        assert status(order) == status
      end

      refute_email_sent()
    end

    test "a hostile tracking URL never reaches the email" do
      order = %Order{
        reference_id: "MRC-X",
        recipient_name: "A B",
        address1: "1",
        city: "C",
        state_code: "CA",
        zip: "9",
        user_id: nil
      }

      shipment = %Shipment{
        tracking_url: "javascript:alert(1)",
        carrier: "X",
        tracking_number: "1",
        reshipment: false
      }

      data = YscWeb.Emails.MerchOrderShipped.prepare_email_data(order, shipment)

      assert data.shipment.tracking_url == nil
    end
  end

  describe "notification audience" do
    test "texts only members who have a phone and have not opted out", %{
      member: member
    } do
      member
      |> Ecto.Changeset.change(account_notifications_sms: false)
      |> Repo.update!()

      order = purchase_order_fixture(member)

      handle("package_shipped", order, %{"shipment" => printful_shipment()})

      assert_email_sent(subject: ~r/on its way/)
      assert sms_messages() == []
    end

    test "no phone, no text" do
      member =
        member_fixture(%{phone_number: nil})
        |> Ecto.Changeset.change(account_notifications_sms: true)
        |> Repo.update!()

      order = purchase_order_fixture(member)

      handle("package_shipped", order, %{"shipment" => printful_shipment()})

      assert_email_sent(subject: ~r/on its way/)
      assert sms_messages() == []
    end

    test "a club-paid order to a custom address emails that address and never texts",
         %{member: _} do
      admin = user_fixture(%{role: "admin"})

      order =
        admin_order_fixture(admin, %{
          status: :submitted,
          printful_order_id: 424_242,
          email: "host@example.com",
          phone: "+14155550123"
        })

      order = Orders.get_order!(order.id)
      handle("package_shipped", order, %{"shipment" => printful_shipment()})

      assert_email_sent(subject: ~r/on its way/, to: {"", "host@example.com"})
      assert sms_messages() == []
    end
  end

  describe "status progression" do
    test "moves forward through production to shipped and never back", %{
      order: order
    } do
      handle("order_updated", order, %{}, %{"status" => "inprocess"})
      assert status(order) == :in_production

      handle("package_shipped", order, %{"shipment" => printful_shipment()})
      assert status(order) == :shipped

      handle("order_updated", order, %{}, %{"status" => "inprocess"})
      assert status(order) == :shipped

      handle("order_updated", order, %{}, %{"status" => "pending"})
      assert status(order) == :shipped
    end

    test "fulfilled with no shipment details still marks the order shipped", %{
      order: order
    } do
      handle("order_updated", order, %{}, %{"status" => "fulfilled"})
      assert status(order) == :shipped
      refute_email_sent()
    end

    test "delivered once every parcel is delivered", %{order: order} do
      a = printful_shipment()
      b = printful_shipment()
      handle("package_shipped", order, %{"shipment" => a})
      handle("package_shipped", order, %{"shipment" => b})
      assert_email_sent(subject: ~r/on its way/)
      assert_email_sent(subject: ~r/on its way/)

      handle("package_delivered", order, %{"shipment" => a})
      assert status(order) == :shipped
      refute_email_sent()

      handle("package_delivered", order, %{"shipment" => b})
      assert status(order) == :delivered
      assert_email_sent(subject: ~r/Your order was delivered/)
    end

    test "a late shipped event does not undo a delivery", %{order: order} do
      shipment = printful_shipment()
      handle("package_shipped", order, %{"shipment" => shipment})
      handle("package_delivered", order, %{"shipment" => shipment})
      handle("package_shipped", order, %{"shipment" => shipment})

      assert status(order) == :delivered

      assert [%Shipment{status: :delivered, delivered_at: delivered_at}] =
               shipments(order)

      assert delivered_at
    end

    test "events for orders that are closed change nothing", %{member: member} do
      for status <- [:delivered, :refunded] do
        order = purchase_order_fixture(member, status)
        handle("order_updated", order, %{}, %{"status" => "inprocess"})
        handle("order_failed", order, %{"reason" => "x"})
        assert status(order) == status
      end
    end
  end

  describe "returned parcels" do
    test "tell the member and the board, once", %{order: order, member: member} do
      shipment = printful_shipment()
      handle("package_shipped", order, %{"shipment" => shipment})
      assert_email_sent(subject: ~r/on its way/)

      handle("package_returned", order, %{"shipment" => shipment})

      assert [%Shipment{status: :returned}] = shipments(order)
      assert_email_sent(subject: ~r/came back to us/, to: {"", member.email})

      assert_email_sent(
        subject: ~r/Merch order needs attention: package returned/,
        to: {"", Ysc.EmailConfig.board_email()}
      )

      handle("package_returned", order, %{"shipment" => shipment})
      refute_email_sent()
    end
  end

  describe "failures" do
    test "order_failed marks it failed and tells the member and the board", %{
      order: order,
      member: member
    } do
      assert :ok =
               handle("order_failed", order, %{
                 "reason" => "Address could not be verified"
               })

      failed = Orders.get_order!(order.id)
      assert failed.status == :failed
      assert failed.failure_reason == "Address could not be verified"

      assert_email_sent(
        subject: ~r/problem with your order/,
        to: {"", member.email}
      )

      assert_email_sent(fn email ->
        assert email.subject =~ "Merch order needs attention"
        assert email.html_body =~ "Address could not be verified"
        assert email.html_body =~ "Refund the payment"
      end)
    end

    test "a repeat of the same failure is silent", %{order: order} do
      handle("order_failed", order, %{"reason" => "x"})
      assert_email_sent()
      assert_email_sent()

      handle("order_failed", order, %{"reason" => "x"})
      refute_email_sent()
    end

    test "order_canceled marks it canceled", %{order: order} do
      handle("order_canceled", order)
      assert status(order) == :canceled
      assert_email_sent(subject: ~r/Your order was canceled/)
    end

    test "a shipped order can no longer fail or be canceled", %{order: order} do
      handle("package_shipped", order, %{"shipment" => printful_shipment()})
      assert_email_sent(subject: ~r/on its way/)

      handle("order_failed", order, %{"reason" => "x"})
      handle("order_canceled", order)

      assert status(order) == :shipped
      refute_email_sent()
    end

    test "the failure text promises a refund only for member purchases", %{
      order: order
    } do
      {_headline, paragraphs} = Ysc.Merch.UpdateCopy.email(:failed, false)
      assert Enum.join(paragraphs, " ") =~ "full refund"

      {_headline, club_paragraphs} = Ysc.Merch.UpdateCopy.email(:failed, true)
      refute Enum.join(club_paragraphs, " ") =~ "refund"
      assert order.kind == :purchase
    end

    test "a hold alerts the board without changing the order", %{order: order} do
      handle("order_put_hold", order, %{"reason" => "Payment method declined"})

      assert status(order) == :submitted

      assert_email_sent(fn email ->
        assert email.subject =~ "on hold at Printful"
        assert email.html_body =~ "Payment method declined"
      end)
    end

    test "a hold waiting for design approval alerts the board", %{order: order} do
      handle("order_put_hold_approval", order, %{
        "reason" => "Print file needs a larger margin",
        "approval_files" => [%{"confirm_hash" => "abc"}]
      })

      assert status(order) == :submitted

      assert_email_sent(fn email ->
        assert email.subject =~ "needs your approval at Printful"
        assert email.html_body =~ "Print file needs a larger margin"
        assert email.html_body =~ "approve it"
      end)
    end

    test "a design approval hold on a shipped order is ignored", %{order: order} do
      handle("package_shipped", order, %{"shipment" => printful_shipment()})
      assert_email_sent(subject: ~r/on its way/)

      handle("order_put_hold_approval", order, %{"reason" => "x"})
      refute_email_sent()
    end

    test "a refund from Printful alerts the board and leaves the order alone",
         %{
           order: order
         } do
      assert :ok = handle("order_refunded", order, %{"amount" => "13.50"})

      assert status(order) == :submitted

      assert_email_sent(fn email ->
        assert email.subject =~ "refunded by Printful"
        assert email.html_body =~ "$13.50"
        assert email.html_body =~ "not refunded automatically"
      end)
    end

    test "the same refund twice alerts once, a different refund alerts again",
         %{
           order: order
         } do
      handle("order_refunded", order, %{"amount" => "13.50"})
      assert_email_sent(subject: ~r/refunded by Printful/)

      handle("order_refunded", order, %{"amount" => "13.50"})
      refute_email_sent()

      handle("order_refunded", order, %{"amount" => "4.00"})
      assert_email_sent(fn email -> assert email.html_body =~ "$4.00" end)
    end

    test "a refund on a club-paid order does not mention refunding a member" do
      admin = user_fixture(%{role: "admin"})
      comp = admin_order_fixture(admin, %{status: :submitted})

      handle("order_refunded", comp, %{"amount" => "20.00"})

      assert_email_sent(fn email ->
        refute email.html_body =~ "not refunded automatically"
        assert email.html_body =~ "place it again"
      end)
    end

    test "a hold on an order that already shipped is ignored", %{order: order} do
      handle("package_shipped", order, %{"shipment" => printful_shipment()})
      assert_email_sent(subject: ~r/on its way/)

      handle("order_put_hold", order, %{"reason" => "x"})
      refute_email_sent()
    end
  end

  describe "subscribed webhook types" do
    test "are the documented events, without the undocumented package_delivered" do
      types = PrintfulEvents.subscribed_types()

      refute "package_delivered" in types
      assert "order_put_hold_approval" in types
      assert "order_refunded" in types
      assert "order_updated" in types
    end
  end

  describe "costs" do
    test "keeps printful_cost current from the order record", %{order: order} do
      handle("order_updated", order, %{}, %{
        "status" => "inprocess",
        "costs" => %{"total" => "31.20"}
      })

      assert Money.equal?(
               Orders.get_order!(order.id).printful_cost,
               Money.new(:USD, "31.20")
             )

      handle("order_updated", order, %{}, %{"costs" => %{"total" => "34.00"}})

      assert Money.equal?(
               Orders.get_order!(order.id).printful_cost,
               Money.new(:USD, "34.00")
             )
    end

    test "ignores missing, zero and malformed costs", %{order: order} do
      handle("order_updated", order, %{}, %{"costs" => %{"total" => "31.20"}})

      for costs <- [
            %{"total" => nil},
            %{"total" => "0.00"},
            %{"total" => "n/a"},
            %{}
          ] do
        handle("order_updated", order, %{}, %{"costs" => costs})
      end

      assert Money.equal?(
               Orders.get_order!(order.id).printful_cost,
               Money.new(:USD, "31.20")
             )
    end

    test "stamps when we last heard from Printful", %{order: order} do
      assert order.printful_synced_at == nil
      handle("order_updated", order)
      assert Orders.get_order!(order.id).printful_synced_at
    end
  end

  describe "events that are not ours" do
    test "unknown orders are ignored", %{order: order} do
      ghost = %{
        order
        | printful_order_id: 999_999_999,
          reference_id: "MRC-000000-ZZZZZ"
      }

      assert :ok =
               handle("package_shipped", ghost, %{
                 "shipment" => printful_shipment()
               })

      assert :ok = handle("order_failed", ghost)
      assert Repo.aggregate(Shipment, :count) == 0
      refute_email_sent()
    end

    test "external ids from other systems are never matched by reference", %{
      order: order
    } do
      other = %{
        order
        | printful_order_id: 888_888_888,
          reference_id: "SHOPIFY-1001"
      }

      assert :ok = handle("order_failed", other)
      assert status(order) == :submitted
    end

    test "falls back to the Printful order id", %{order: order} do
      payload =
        printful_event("order_updated", order, %{}, %{
          "external_id" => nil,
          "status" => "inprocess"
        })

      assert :ok = PrintfulEvents.handle_event(payload["type"], payload["data"])
      assert status(order) == :in_production
    end

    test "unknown event types and malformed payloads are accepted", %{
      order: order
    } do
      assert :ok = handle("product_updated", order)
      assert :ok = handle("order_refunded", order)
      assert :ok = handle("order_remove_hold", order)
      assert :ok = PrintfulEvents.handle_event("order_updated", %{})
      assert :ok = PrintfulEvents.handle_event(nil, nil)
      assert status(order) == :submitted
    end
  end

  describe "what is in each parcel" do
    # An order of two different lines, one of each, and Printful's record of
    # it: each item has an id of its own that shipments refer to.
    setup do
      # Someone with an empty cart, so the order is exactly these two lines.
      member = member_fixture()
      sticker = variant_fixture(nil, %{name: "Sticker Sheet"})
      pin = variant_fixture(nil, %{name: "Flag Pin"})
      lines = cart_lines_fixture(member, [{sticker, 1}, {pin, 1}])

      {:ok, pending} =
        Orders.create_pending_purchase(
          member,
          lines,
          shipping_address_fixture(),
          shipping_option_fixture()
        )

      order =
        pending
        |> Ecto.Changeset.change(
          status: :submitted,
          printful_order_id: System.unique_integer([:positive]) + 1_000
        )
        |> Repo.update!()
        |> then(&Orders.get_order!(&1.id))

      printful_items = [
        %{"id" => 1001, "sync_variant_id" => sticker.printful_sync_variant_id},
        %{"id" => 1002, "sync_variant_id" => pin.printful_sync_variant_id}
      ]

      line = fn variant ->
        Enum.find(order.items, &(&1.variant_id == variant.id))
      end

      %{
        buyer: member,
        two: order,
        printful_items: printful_items,
        sticker_line: line.(sticker),
        pin_line: line.(pin)
      }
    end

    # The next email sent, as {html, to}.
    defp next_email do
      assert_received {:email, %Swoosh.Email{html_body: html, to: to}}
      {html, to}
    end

    defp ship(order, printful_items, shipment) do
      handle("package_shipped", order, %{"shipment" => shipment}, %{
        "items" => printful_items,
        "status" => "partial"
      })
    end

    defp parcel(item_id, attrs \\ %{}) do
      printful_shipment(
        Map.merge(
          %{"items" => [%{"item_id" => item_id, "quantity" => 1}]},
          attrs
        )
      )
    end

    test "a parcel records the order lines it holds and the email lists only those",
         %{
           two: order,
           printful_items: items,
           sticker_line: sticker_line,
           buyer: buyer
         } do
      ship(order, items, parcel(1001))

      assert [recorded] = shipments(order)

      assert recorded.items == [
               %{"order_item_id" => sticker_line.id, "quantity" => 1}
             ]

      {html, to} = next_email()
      assert to == [{"", buyer.email}]
      assert html =~ "Sticker Sheet"
      refute html =~ "Flag Pin"
      assert html =~ "In this package"
      assert html =~ "more than one package"
    end

    test "the other parcel lists the other item", %{
      two: order,
      printful_items: items
    } do
      ship(order, items, parcel(1001))
      next_email()

      ship(order, items, parcel(1002))

      {html, _to} = next_email()
      assert html =~ "Flag Pin"
      refute html =~ "Sticker Sheet"

      assert length(shipments(order)) == 2
    end

    test "one parcel holding everything is the whole order, not part of it", %{
      two: order,
      printful_items: items
    } do
      shipment =
        printful_shipment(%{
          "items" => [
            %{"item_id" => 1001, "quantity" => 1},
            %{"item_id" => 1002, "quantity" => 1}
          ]
        })

      ship(order, items, shipment)

      {html, _to} = next_email()
      assert html =~ "Sticker Sheet"
      assert html =~ "Flag Pin"
      assert html =~ "Your order"
      refute html =~ "more than one package"
    end

    test "a parcel we cannot place shows the whole order, not part of it", %{
      two: order,
      printful_items: items
    } do
      # An item id Printful's order record does not list.
      ship(order, items, parcel(9999))

      assert [%Shipment{items: []}] = shipments(order)

      {html, _to} = next_email()
      assert html =~ "Sticker Sheet"
      assert html =~ "Flag Pin"
      refute html =~ "more than one package"
    end

    test "no item detail from Printful at all falls back to the whole order",
         %{two: order} do
      handle("package_shipped", order, %{"shipment" => printful_shipment()})

      assert [%Shipment{items: []}] = shipments(order)

      {html, _to} = next_email()
      assert html =~ "Sticker Sheet"
      assert html =~ "Flag Pin"
    end

    test "a quantity beyond what was ordered is capped, a missing one is the line's",
         %{
           two: order,
           printful_items: items,
           sticker_line: sticker_line,
           pin_line: pin_line
         } do
      ship(
        order,
        items,
        parcel(1001, %{"items" => [%{"item_id" => 1001, "quantity" => 5}]})
      )

      ship(
        order,
        items,
        printful_shipment(%{"items" => [%{"item_id" => 1002}]})
      )

      parcels =
        order
        |> shipments()
        |> Enum.flat_map(& &1.items)
        |> Enum.sort_by(& &1["order_item_id"])

      assert parcels ==
               Enum.sort_by(
                 [
                   %{"order_item_id" => sticker_line.id, "quantity" => 1},
                   %{"order_item_id" => pin_line.id, "quantity" => 1}
                 ],
                 & &1["order_item_id"]
               )
    end

    test "malformed item entries are skipped, not fatal", %{
      two: order,
      printful_items: items
    } do
      shipment =
        printful_shipment(%{
          "items" => [nil, "oops", %{"item_id" => "x"}, %{"item_id" => 1001}]
        })

      assert :ok = ship(order, items, shipment)
      assert [%Shipment{items: [%{"quantity" => 1}]}] = shipments(order)
    end

    test "a later event fills in items a shipment was first recorded without",
         %{two: order, printful_items: items, pin_line: pin_line} do
      shipment = printful_shipment()
      handle("package_shipped", order, %{"shipment" => shipment})
      assert [%Shipment{items: []}] = shipments(order)

      ship(
        order,
        items,
        Map.put(shipment, "items", [%{"item_id" => 1002, "quantity" => 1}])
      )

      assert [%Shipment{items: [%{"order_item_id" => id}]}] = shipments(order)
      assert id == pin_line.id
    end

    test "a later event without items does not erase the recorded ones", %{
      two: order,
      printful_items: items
    } do
      shipment = parcel(1001)
      ship(order, items, shipment)

      handle("package_shipped", order, %{
        "shipment" => Map.delete(shipment, "items")
      })

      assert [%Shipment{items: [_]}] = shipments(order)
    end
  end

  describe "announcing a shipment" do
    test "waits for a tracking number and then announces it once", %{
      order: order
    } do
      shipment =
        printful_shipment(%{"tracking_number" => nil, "tracking_url" => nil})

      handle("package_shipped", order, %{"shipment" => shipment})

      assert [recorded] = shipments(order)
      assert recorded.status == :shipped
      assert is_nil(recorded.notified_at)
      assert status(order) == :shipped
      refute_email_sent()
      assert sms_messages() == []

      # Printful reports it again, now with the label.
      handle("package_shipped", order, %{
        "shipment" =>
          Map.merge(shipment, %{
            "tracking_number" => "9400111899223197428490",
            "tracking_url" =>
              "https://carrier.example.test/9400111899223197428490"
          })
      })

      assert_email_sent(fn email ->
        assert email.html_body =~ "9400111899223197428490"
      end)

      assert [%Shipment{notified_at: %DateTime{}}] = shipments(order)

      # And never again.
      handle("package_shipped", order, %{"shipment" => shipment})
      refute_email_sent()
      assert length(sms_messages()) == 1
    end

    test "the poll announces it once the tracking number has appeared", %{
      order: order
    } do
      untracked =
        printful_shipment(%{"tracking_number" => nil, "tracking_url" => nil})

      sync = fn shipment ->
        PrintfulEvents.sync_order(order, %{
          "id" => order.printful_order_id,
          "status" => "fulfilled",
          "shipments" => [shipment]
        })
      end

      sync.(untracked)
      refute_email_sent()

      sync.(Map.put(untracked, "tracking_number", "TRACK123"))
      assert_email_sent(subject: ~r/on its way/)
    end

    test "goes out without tracking once the wait is over", %{order: order} do
      seven_hours_ago = System.os_time(:second) - 7 * 3600

      shipment =
        printful_shipment(%{
          "tracking_number" => nil,
          "tracking_url" => nil,
          "shipped_at" => seven_hours_ago
        })

      handle("package_shipped", order, %{"shipment" => shipment})

      assert_email_sent(fn email ->
        assert email.html_body =~ "tracking number isn&#39;t available" or
                 email.html_body =~ "tracking number isn't available"
      end)

      assert [%Shipment{notified_at: %DateTime{}}] = shipments(order)
    end

    test "a link with no tracking number behind it is not kept or sent", %{
      order: order
    } do
      shipment =
        printful_shipment(%{
          "tracking_number" => "  ",
          "tracking_url" => "https://myorders.co/tracking/1/"
        })

      handle("package_shipped", order, %{"shipment" => shipment})

      assert [%Shipment{tracking_number: nil, tracking_url: nil}] =
               shipments(order)
    end

    test "blank and oversized values are cleaned up, not fatal", %{
      order: order
    } do
      shipment =
        printful_shipment(%{
          "carrier" => "   ",
          "service" => String.duplicate("s", 400),
          "tracking_number" => "  ABC123  ",
          "tracking_url" =>
            "https://carrier.example.test/" <> String.duplicate("x", 2_000)
        })

      assert :ok = handle("package_shipped", order, %{"shipment" => shipment})

      assert [recorded] = shipments(order)
      assert recorded.carrier == nil
      assert String.length(recorded.service) == 255
      assert recorded.tracking_number == "ABC123"
      assert recorded.tracking_url == nil
    end

    test "a long tracking link is stored whole", %{order: order} do
      url = "https://carrier.example.test/" <> String.duplicate("x", 400)

      handle("package_shipped", order, %{
        "shipment" => printful_shipment(%{"tracking_url" => url})
      })

      assert [%Shipment{tracking_url: ^url}] = shipments(order)
    end

    test "a shipment Printful still calls pending is not announced even by a shipped event",
         %{order: order} do
      assert :ok =
               handle("package_shipped", order, %{
                 "shipment" => printful_shipment(%{"status" => "pending"})
               })

      assert shipments(order) == []
      assert status(order) == :submitted
      refute_email_sent()
    end

    test "a later event corrects the ship time", %{order: order} do
      shipment = printful_shipment(%{"shipped_at" => 1_700_000_000})
      handle("package_shipped", order, %{"shipment" => shipment})

      later = 1_700_000_999

      handle("package_shipped", order, %{
        "shipment" => Map.put(shipment, "shipped_at", later)
      })

      assert [%Shipment{shipped_at: shipped_at}] = shipments(order)
      assert DateTime.to_unix(shipped_at) == later
    end

    test "a parcel the poll finds already delivered is recorded, not announced",
         %{order: order} do
      shipment = printful_shipment(%{"status" => "delivered"})

      PrintfulEvents.sync_order(order, %{
        "id" => order.printful_order_id,
        "status" => "fulfilled",
        "shipments" => [shipment]
      })

      assert [%Shipment{status: :delivered}] = shipments(order)
      assert status(order) == :shipped
      refute_email_sent()
      assert sms_messages() == []
    end
  end

  describe "sync_order/2 (polling)" do
    test "applies status, cost and shipments from a full order record", %{
      order: order,
      member: member
    } do
      printful_order = %{
        "id" => order.printful_order_id,
        "external_id" => order.reference_id,
        "status" => "fulfilled",
        "costs" => %{"total" => "28.00"},
        "shipments" => [printful_shipment()]
      }

      assert :ok = PrintfulEvents.sync_order(order, printful_order)

      synced = Orders.get_order!(order.id)
      assert synced.status == :shipped
      assert Money.equal?(synced.printful_cost, Money.new(:USD, "28.00"))
      assert length(synced.shipments) == 1
      assert_email_sent(subject: ~r/on its way/, to: {"", member.email})
    end

    # As Printful returned a freshly placed order (live API): shipments are
    # listed right away, each "pending" with no tracking number.
    defp pending_shipment(attrs \\ %{}) do
      Map.merge(
        %{
          "id" => System.unique_integer([:positive]) + 9_000,
          "carrier" => nil,
          "service" => nil,
          "status" => "pending",
          "ship_date" => nil,
          "shipped_at" => nil,
          "tracking_number" => nil,
          "tracking_url" => "https://myorders.co/tracking/1/",
          "reshipment" => false
        },
        attrs
      )
    end

    test "shipments Printful lists but has not shipped do not ship the order",
         %{
           order: order
         } do
      printful_order = %{
        "id" => order.printful_order_id,
        "external_id" => order.reference_id,
        "status" => "pending",
        "shipments" => [pending_shipment(), pending_shipment()]
      }

      assert :ok = PrintfulEvents.sync_order(order, printful_order)

      assert status(order) == :submitted
      assert shipments(order) == []
      refute_email_sent()
      assert sms_messages() == []
    end

    test "only the shipments that left are recorded and announced", %{
      order: order
    } do
      shipped =
        printful_shipment(%{"status" => "shipped", "carrier" => "USPS"})

      printful_order = %{
        "id" => order.printful_order_id,
        "external_id" => order.reference_id,
        "status" => "partial",
        "shipments" => [shipped, pending_shipment()]
      }

      assert :ok = PrintfulEvents.sync_order(order, printful_order)

      assert [recorded] = shipments(order)
      assert recorded.printful_shipment_id == shipped["id"]
      assert status(order) == :shipped
      assert_email_sent(subject: ~r/on its way/)
    end

    test "a malformed entry in the shipments list is skipped, not fatal", %{
      order: order
    } do
      assert :ok =
               PrintfulEvents.sync_order(order, %{
                 "id" => order.printful_order_id,
                 "status" => "pending",
                 "shipments" => [nil, "oops", pending_shipment()]
               })

      assert shipments(order) == []
      assert status(order) == :submitted
    end

    test "a pending shipment with an estimated ship date still does not ship the order",
         %{
           order: order
         } do
      # Printful often puts an estimated date on a still-pending parcel as soon
      # as the order is placed. Status is authoritative when present.
      printful_order = %{
        "id" => order.printful_order_id,
        "external_id" => order.reference_id,
        "status" => "pending",
        "shipments" => [
          pending_shipment(%{
            "ship_date" => "2026-10-21",
            "shipped_at" => System.os_time(:second)
          })
        ]
      }

      assert :ok = PrintfulEvents.sync_order(order, printful_order)

      assert status(order) == :submitted
      assert shipments(order) == []
      refute_email_sent()
      assert sms_messages() == []
    end

    test "a shipment with no status but a ship date counts as shipped", %{
      order: order
    } do
      shipment = printful_shipment() |> Map.delete("status")

      PrintfulEvents.sync_order(order, %{
        "id" => order.printful_order_id,
        "status" => "fulfilled",
        "shipments" => [shipment]
      })

      assert length(shipments(order)) == 1
    end

    test "polling after a webhook does not notify again", %{order: order} do
      shipment = printful_shipment()
      handle("package_shipped", order, %{"shipment" => shipment})
      assert_email_sent(subject: ~r/on its way/)

      PrintfulEvents.sync_order(
        Orders.get_order!(order.id),
        %{
          "id" => order.printful_order_id,
          "status" => "fulfilled",
          "shipments" => [shipment]
        }
      )

      refute_email_sent()
      assert length(shipments(order)) == 1
    end

    test "maps in-process and partial to in production", %{member: member} do
      for printful_status <- ["inprocess", "partial"] do
        order = purchase_order_fixture(member, :submitted)

        PrintfulEvents.sync_order(order, %{
          "id" => order.printful_order_id,
          "status" => printful_status
        })

        assert status(order) == :in_production
      end
    end

    test "a failed or canceled record closes the order", %{member: member} do
      failed = purchase_order_fixture(member, :submitted)

      PrintfulEvents.sync_order(failed, %{
        "id" => failed.printful_order_id,
        "status" => "failed",
        "error" => "Out of stock"
      })

      assert Orders.get_order!(failed.id).failure_reason == "Out of stock"
      assert status(failed) == :failed

      canceled = purchase_order_fixture(member, :in_production)

      PrintfulEvents.sync_order(canceled, %{
        "id" => canceled.printful_order_id,
        "status" => "canceled"
      })

      assert status(canceled) == :canceled
    end
  end
end
