defmodule YscWeb.Emails.MerchEmailsTest do
  use Ysc.DataCase, async: true

  import Ysc.MerchFixtures

  alias Ysc.Merch.{Orders, Shipment}

  alias YscWeb.Emails.{
    MerchAdminOrderBoardNotification,
    MerchItems,
    MerchOrderAttentionBoardNotification,
    MerchOrderConfirmation,
    MerchOrderShipped,
    MerchOrderUpdate
  }

  alias YscWeb.Sms

  setup do
    member = member_fixture()
    %{order: purchase_order_fixture(member, :submitted), member: member}
  end

  defp shipment(attrs \\ %{}) do
    struct!(
      Shipment,
      Map.merge(
        %{
          id: Ecto.ULID.generate(),
          printful_shipment_id: 1,
          carrier: "USPS",
          service: "Priority Mail",
          tracking_number: "9400111899223197428490",
          tracking_url: "https://tools.usps.com/track?x=1",
          reshipment: false
        },
        attrs
      )
    )
  end

  describe "items in every merch email" do
    setup %{order: order} do
      image =
        image_fixture(%{raw_image_path: "https://media.example.test/tee.jpg"})

      for item <- order.items do
        item.variant
        |> Ecto.Changeset.change(image_id: image.id)
        |> Repo.update!()
      end

      %{order: Orders.get_order!(order.id)}
    end

    defp assert_lists_items(html, order) do
      for item <- order.items do
        assert html =~ "Club Tee"
        assert html =~ "Black · M"
        assert html =~ "&times; #{item.quantity}"
      end

      assert html =~ ~s(src="https://media.example.test/tee.jpg")
    end

    test "confirmation lists the items with a thumbnail and prices", %{
      order: order
    } do
      html =
        order
        |> MerchOrderConfirmation.prepare_email_data()
        |> MerchOrderConfirmation.render()

      assert html =~ "We've got your order"
      assert html =~ "we're making your items now"
      refute html =~ "merch"
      refute html =~ "printer"
      assert html =~ "Club Tee"
      assert html =~ "Black · M"
      assert html =~ ~s(src="https://media.example.test/tee.jpg")
      # Quantity, unit price and line total are still there.
      assert html =~ "$25.00"
      assert html =~ "$50.00"
    end

    test "the confirmation's item table has two columns, so it fits a phone", %{
      order: order
    } do
      html =
        order
        |> MerchOrderConfirmation.prepare_email_data()
        |> MerchOrderConfirmation.render()

      # Quantity and unit price sit under the item name, not in their own
      # columns (which shrank to a few characters wide on mobile).
      assert html =~ "2 &times; $25.00"
      refute html =~ ">Qty<"
      refute html =~ ">Price<"
      assert html =~ ">Total<"
    end

    test "the confirmation's order number label is bold, like the date's", %{
      order: order
    } do
      html =
        order
        |> MerchOrderConfirmation.prepare_email_data()
        |> MerchOrderConfirmation.render()

      assert html =~ "<strong>Order number:</strong>"
      assert html =~ "<strong>Ordered:</strong>"
    end

    test "the confirmation subject names the order, not merch", %{order: order} do
      assert MerchOrderConfirmation.get_subject(order) ==
               "We've got your order (#{order.reference_id})"
    end

    test "shipped", %{order: order} do
      order
      |> MerchOrderShipped.prepare_email_data(shipment())
      |> MerchOrderShipped.render()
      |> assert_lists_items(order)
    end

    test "every kind of update", %{order: order} do
      for kind <- [:delivered, :returned, :failed, :canceled] do
        kind
        |> MerchOrderUpdate.prepare_email_data(order)
        |> MerchOrderUpdate.render()
        |> assert_lists_items(order)
      end
    end

    test "board alert", %{order: order} do
      :submit_failed
      |> MerchOrderAttentionBoardNotification.prepare_email_data(order, "Boom")
      |> MerchOrderAttentionBoardNotification.render()
      |> assert_lists_items(order)
    end

    test "falls back to the product photo, then to no photo", %{order: order} do
      [item | _] = order.items

      product_image =
        image_fixture(%{
          raw_image_path: "https://media.example.test/product.jpg"
        })

      item.variant |> Ecto.Changeset.change(image_id: nil) |> Repo.update!()

      Repo.get!(Ysc.Merch.Product, item.variant.product_id)
      |> Ecto.Changeset.change(image_id: product_image.id)
      |> Repo.update!()

      assert [%{thumbnail: "https://media.example.test/product.jpg"}] =
               order.id |> Orders.get_order!() |> MerchItems.for_order()

      Repo.get!(Ysc.Merch.Product, item.variant.product_id)
      |> Ecto.Changeset.change(image_id: nil)
      |> Repo.update!()

      [bare] = order.id |> Orders.get_order!() |> MerchItems.for_order()
      assert bare.thumbnail == nil

      html =
        MerchOrderUpdate.prepare_email_data(
          :delivered,
          Orders.get_order!(order.id)
        )
        |> MerchOrderUpdate.render()

      # Still listed, just without a picture.
      assert html =~ "Club Tee"
      refute html =~ "<img src=\"https://media"
    end

    test "a site-relative image path becomes an absolute URL", %{order: order} do
      relative = image_fixture(%{raw_image_path: "/uploads/tee.jpg"})

      for item <- order.items do
        item.variant
        |> Ecto.Changeset.change(image_id: relative.id)
        |> Repo.update!()
      end

      [%{thumbnail: url} | _] =
        order.id |> Orders.get_order!() |> MerchItems.for_order()

      assert url == YscWeb.Endpoint.url() <> "/uploads/tee.jpg"
    end

    test "a hostile item name cannot inject markup", %{order: order} do
      [item | _] = order.items

      item
      |> Ecto.Changeset.change(name: "<script>alert(1)</script> / <b>x</b>")
      |> Repo.update!()

      html =
        MerchOrderUpdate.prepare_email_data(
          :delivered,
          Orders.get_order!(order.id)
        )
        |> MerchOrderUpdate.render()

      refute html =~ "<script>alert(1)</script>"
      assert html =~ "&lt;script&gt;"
    end

    test "club-paid order emails list items too", %{} do
      admin = Ysc.AccountsFixtures.user_fixture(%{role: "admin"})

      image =
        image_fixture(%{raw_image_path: "https://media.example.test/gift.jpg"})

      variant = variant_fixture(nil, %{name: "Sticker Pack / Blue"})
      variant |> Ecto.Changeset.change(image_id: image.id) |> Repo.update!()

      order =
        admin
        |> admin_order_fixture(%{items: [{variant, 20}]})
        |> then(&Orders.get_order_for_email!(&1.id))

      for html <- [
            order
            |> MerchOrderConfirmation.prepare_email_data()
            |> MerchOrderConfirmation.render(),
            order
            |> MerchAdminOrderBoardNotification.prepare_email_data()
            |> MerchAdminOrderBoardNotification.render()
          ] do
        assert html =~ "Sticker Pack"
        assert html =~ "Blue"
        assert html =~ ~s(src="https://media.example.test/gift.jpg")
      end
    end
  end

  describe "estimated delivery" do
    defp with_estimate(order) do
      min = Date.add(Date.utc_today(), 5)

      %{
        order
        | delivery_estimate_min: min,
          delivery_estimate_max: Date.add(min, 2)
      }
    end

    test "the confirmation says when it should arrive", %{order: order} do
      order = with_estimate(order)
      estimate = Ysc.Merch.Shipping.delivery_estimate(order)

      html =
        order
        |> MerchOrderConfirmation.prepare_email_data()
        |> MerchOrderConfirmation.render()

      assert html =~ "Estimated delivery: #{estimate}"
    end

    test "the confirmation has no delivery line without an estimate", %{
      order: order
    } do
      html =
        order
        |> MerchOrderConfirmation.prepare_email_data()
        |> MerchOrderConfirmation.render()

      refute html =~ "Estimated delivery"
    end

    test "the shipped email replaces its generic line with the estimate", %{
      order: order
    } do
      order = with_estimate(order)
      estimate = Ysc.Merch.Shipping.delivery_estimate(order)

      html =
        order
        |> MerchOrderShipped.prepare_email_data(shipment())
        |> MerchOrderShipped.render()

      assert html =~ "Estimated delivery: #{estimate}"
      refute html =~ "Delivery usually takes a few business days"
    end

    test "the shipped email keeps its generic line without one", %{order: order} do
      html =
        order
        |> MerchOrderShipped.prepare_email_data(shipment())
        |> MerchOrderShipped.render()

      assert html =~ "Delivery usually takes a few business days"
    end

    test "the shipped text message includes it", %{order: order} do
      order = with_estimate(order)
      estimate = Ysc.Merch.Shipping.delivery_estimate(order)

      text =
        order
        |> Sms.MerchOrderShipped.prepare_sms_data(shipment())
        |> Sms.MerchOrderShipped.render()

      assert text =~ "Est. delivery #{estimate}"
      assert text =~ "has shipped via USPS"
    end

    test "the shipped text message is unchanged without one", %{order: order} do
      text =
        order
        |> Sms.MerchOrderShipped.prepare_sms_data(shipment())
        |> Sms.MerchOrderShipped.render()

      refute text =~ "Est. delivery"
    end
  end

  describe "club-paid order board email" do
    setup do
      admin =
        Ysc.AccountsFixtures.user_fixture(%{
          role: "admin",
          first_name: "Lars",
          last_name: "Nilsson"
        })

      event = Ysc.EventsFixtures.event_fixture()

      order =
        admin
        |> admin_order_fixture(%{
          event_id: event.id,
          purpose: "Happy hour <giveaway>",
          estimated_cost: Money.new(:USD, "118.40"),
          items: [{variant_fixture(nil, %{name: "Club Tee / Black / M"}), 5}]
        })
        |> then(&Orders.get_order_for_email!(&1.id))

      %{admin: admin, event: event, club_order: order}
    end

    test "names who placed it, why, what and what it costs", %{
      admin: admin,
      event: event,
      club_order: order
    } do
      html =
        order
        |> MerchAdminOrderBoardNotification.prepare_email_data()
        |> MerchAdminOrderBoardNotification.render()

      assert html =~ "Club-paid merch order"
      assert html =~ "Lars Nilsson"
      assert html =~ admin.email
      assert html =~ order.reference_id
      assert html =~ "Ada Admin"
      assert html =~ "1 Market St"
      assert html =~ "Club Tee"
      assert html =~ "Black · M"
      assert html =~ "&times; 5"
      assert html =~ "$118.40"
      assert html =~ event.title
      assert html =~ "/admin/merch/orders/#{order.id}"
      assert html =~ "/admin/users/#{admin.id}/details"
    end

    test "escapes the free-text purpose", %{club_order: order} do
      html =
        order
        |> MerchAdminOrderBoardNotification.prepare_email_data()
        |> MerchAdminOrderBoardNotification.render()

      refute html =~ "<giveaway>"
      assert html =~ "&lt;giveaway&gt;"
    end

    test "says so when there is no estimate yet", %{club_order: order} do
      html =
        %{order | estimated_cost: nil}
        |> MerchAdminOrderBoardNotification.prepare_email_data()
        |> MerchAdminOrderBoardNotification.render()

      assert html =~ "Not available yet"
    end

    test "the subject names the admin", %{club_order: order} do
      assert MerchAdminOrderBoardNotification.get_subject(order) ==
               "Lars Nilsson placed a club-paid merch order (#{order.reference_id})"
    end

    test "a member recipient is described, and an admin ordering for themselves too",
         %{admin: admin, club_order: order} do
      member = member_fixture(%{first_name: "Astrid", last_name: "Berg"})

      for_member =
        MerchAdminOrderBoardNotification.prepare_email_data(%{
          order
          | user: member,
            granted_by_id: admin.id
        })

      assert for_member.recipient.detail =~ member.email

      for_self =
        MerchAdminOrderBoardNotification.prepare_email_data(%{
          order
          | user: admin,
            granted_by_id: admin.id
        })

      assert for_self.recipient.detail =~ "admin who placed"
    end
  end

  describe "shipped email" do
    test "renders carrier, tracking and a track button", %{order: order} do
      html =
        order
        |> MerchOrderShipped.prepare_email_data(shipment())
        |> MerchOrderShipped.render()

      assert html =~ "Your order is on its way"
      refute html =~ "merch"
      assert html =~ "Shipped by:"
      refute html =~ "Carrier:"
      assert html =~ order.reference_id
      assert html =~ "USPS"
      assert html =~ "9400111899223197428490"
      assert html =~ "https://tools.usps.com/track?x=1"
      assert html =~ "Track your package"
      assert html =~ "Ada Lovelace"
    end

    test "copes with no tracking details", %{order: order} do
      html =
        order
        |> MerchOrderShipped.prepare_email_data(
          shipment(%{
            carrier: nil,
            service: nil,
            tracking_number: nil,
            tracking_url: nil
          })
        )
        |> MerchOrderShipped.render()

      assert html =~ "A tracking number isn't available yet"
      refute html =~ "hasn't shared a tracking number yet"
      refute html =~ "Track your package"
    end

    test "says replacement for a reshipment", %{order: order} do
      html =
        order
        |> MerchOrderShipped.prepare_email_data(shipment(%{reshipment: true}))
        |> MerchOrderShipped.render()

      assert html =~ "A replacement for order"
    end

    test "a partial parcel lists that quantity and says the rest ships separately",
         %{order: order} do
      [item] = order.items
      assert item.quantity == 2

      data =
        MerchOrderShipped.prepare_email_data(
          order,
          shipment(%{
            items: [%{"order_item_id" => item.id, "quantity" => 1}]
          })
        )

      assert data.part_of_order
      assert [%{name: "Club Tee", quantity: 1}] = data.items

      html = MerchOrderShipped.render(data)
      assert html =~ "In this package"
      assert html =~ "more than one package"
      assert html =~ "&times; 1"
      refute html =~ "&times; 2"
    end

    test "a replacement of a partial parcel does not say the order is split",
         %{order: order} do
      [item] = order.items

      html =
        order
        |> MerchOrderShipped.prepare_email_data(
          shipment(%{
            items: [%{"order_item_id" => item.id, "quantity" => 1}],
            reshipment: true
          })
        )
        |> MerchOrderShipped.render()

      assert html =~ "A replacement for order"
      refute html =~ "In this package"
      refute html =~ "more than one package"
    end

    test "never links to a non-http tracking URL", %{order: order} do
      html =
        order
        |> MerchOrderShipped.prepare_email_data(
          shipment(%{tracking_url: "javascript:alert(1)"})
        )
        |> MerchOrderShipped.render()

      refute html =~ "javascript:"
      refute html =~ "Track your package"
    end

    test "subject and template name", %{order: order} do
      assert MerchOrderShipped.get_subject(order) ==
               "Your order is on its way (#{order.reference_id})"

      assert MerchOrderShipped.get_template_name() == "merch_order_shipped"
    end
  end

  describe "update email" do
    for kind <- [:delivered, :returned, :failed, :canceled] do
      test "renders #{kind}", %{order: order} do
        html =
          unquote(kind)
          |> MerchOrderUpdate.prepare_email_data(order)
          |> MerchOrderUpdate.render()

        {headline, _} = Ysc.Merch.UpdateCopy.email(unquote(kind), false)

        assert html =~
                 headline
                 |> Phoenix.HTML.html_escape()
                 |> Phoenix.HTML.safe_to_string()

        assert html =~ order.reference_id

        assert MerchOrderUpdate.get_subject(unquote(kind), order) =~
                 order.reference_id
      end
    end

    test "club-paid orders never mention a refund" do
      for kind <- [:failed, :canceled] do
        {_, paragraphs} = Ysc.Merch.UpdateCopy.email(kind, true)
        refute Enum.join(paragraphs, " ") =~ "refund"
      end
    end

    test "members of the shop get a link to the order, strangers get the shop",
         %{order: order} do
      assert MerchOrderUpdate.prepare_email_data(:delivered, order).order_url =~
               "/shop/orders/#{order.id}"

      admin = Ysc.AccountsFixtures.user_fixture(%{role: "admin"})

      custom =
        admin
        |> admin_order_fixture(%{status: :submitted})
        |> then(&Orders.get_order!(&1.id))

      refute custom.user_id

      assert String.ends_with?(
               MerchOrderUpdate.prepare_email_data(:delivered, custom).order_url,
               "/shop"
             )
    end
  end

  describe "board alert" do
    test "explains what happened and what to do", %{order: order} do
      for kind <- [:submit_failed, :failed, :canceled, :on_hold, :returned] do
        data =
          MerchOrderAttentionBoardNotification.prepare_email_data(
            kind,
            order,
            "Because reasons"
          )

        html = MerchOrderAttentionBoardNotification.render(data)

        assert html =~ "Merch order needs attention"
        assert html =~ order.reference_id
        assert html =~ "Because reasons"
        assert html =~ "Club Tee"
        assert html =~ "/admin/merch"

        assert MerchOrderAttentionBoardNotification.get_subject(kind, order) =~
                 order.reference_id
      end
    end

    test "points at a refund for a paid member order that cannot ship", %{
      order: order
    } do
      for kind <- [:submit_failed, :failed, :canceled] do
        assert MerchOrderAttentionBoardNotification.action(kind, order) =~
                 "Refund the payment"
      end
    end

    test "club-paid orders get a different instruction" do
      admin = Ysc.AccountsFixtures.user_fixture(%{role: "admin"})

      comp =
        admin
        |> admin_order_fixture(%{status: :submitted})
        |> then(&Orders.get_order!(&1.id))

      action = MerchOrderAttentionBoardNotification.action(:failed, comp)
      refute action =~ "Refund"
      assert action =~ "club-paid"
    end

    test "holds point at Printful billing", %{order: order} do
      assert MerchOrderAttentionBoardNotification.action(:on_hold, order) =~
               "billing"
    end
  end

  describe "confirmation email for a club-paid order" do
    test "says the club is covering it and shows the purpose" do
      admin = Ysc.AccountsFixtures.user_fixture(%{role: "admin"})

      comp =
        admin
        |> admin_order_fixture(%{
          status: :submitted,
          purpose: "Happy hour giveaway"
        })
        |> then(&Orders.get_order!(&1.id))

      html =
        comp
        |> MerchOrderConfirmation.prepare_email_data()
        |> MerchOrderConfirmation.render()

      assert html =~ "We've got your order"
      refute html =~ "merch"
      assert html =~ "the club is covering it"
      assert html =~ "Happy hour giveaway"
      assert html =~ "Paid by the club"
    end
  end

  describe "SMS" do
    test "shipped text includes carrier and tracking link", %{order: order} do
      data = Sms.MerchOrderShipped.prepare_sms_data(order, shipment(), "Astrid")
      body = Sms.MerchOrderShipped.render(data)

      assert body =~ "[YSC]"
      assert body =~ "Hej Astrid!"
      assert body =~ order.reference_id
      assert body =~ "via USPS"
      assert body =~ "https://tools.usps.com/track?x=1"
    end

    test "shipped text works without tracking and drops unsafe links", %{
      order: order
    } do
      plain =
        Sms.MerchOrderShipped.prepare_sms_data(
          order,
          shipment(%{carrier: nil, tracking_url: nil})
        )

      body = Sms.MerchOrderShipped.render(plain)
      assert body =~ "has shipped."
      refute body =~ "Track it"

      unsafe =
        Sms.MerchOrderShipped.prepare_sms_data(
          order,
          shipment(%{tracking_url: "javascript:alert(1)"})
        )

      refute Sms.MerchOrderShipped.render(unsafe) =~ "javascript:"
    end

    test "update texts for every kind", %{order: order} do
      for kind <- Ysc.Merch.UpdateCopy.kinds() do
        body =
          kind
          |> Sms.MerchOrderUpdate.prepare_sms_data(order, "Astrid")
          |> Sms.MerchOrderUpdate.render()

        assert body =~ order.reference_id
        assert body =~ "[YSC]"
      end
    end

    test "update texts survive the JSON round trip of an Oban job", %{
      order: order
    } do
      data = Sms.MerchOrderUpdate.prepare_sms_data(:returned, order)

      assert Sms.MerchOrderUpdate.render(%{data | kind: "returned"}) =~
               "returned to sender"

      assert Sms.MerchOrderUpdate.render(%{data | kind: "gibberish"}) =~
               "delivered"
    end
  end
end
