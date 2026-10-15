defmodule YscWeb.Emails.MerchEmailsTest do
  use Ysc.DataCase, async: true

  import Ysc.MerchFixtures

  alias Ysc.Merch.{Orders, Shipment}

  alias YscWeb.Emails.{
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

  describe "shipped email" do
    test "renders carrier, tracking and a track button", %{order: order} do
      html =
        order
        |> MerchOrderShipped.prepare_email_data(shipment())
        |> MerchOrderShipped.render()

      assert html =~ "Your merch is on its way"
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

      assert html =~ "hasn't shared a tracking number yet"
      refute html =~ "Track your package"
    end

    test "says replacement for a reshipment", %{order: order} do
      html =
        order
        |> MerchOrderShipped.prepare_email_data(shipment(%{reshipment: true}))
        |> MerchOrderShipped.render()

      assert html =~ "A replacement for order"
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
               "Your merch is on its way (#{order.reference_id})"

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
