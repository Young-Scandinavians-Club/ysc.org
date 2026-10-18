defmodule Ysc.Merch.StripeServiceTest do
  use Ysc.DataCase, async: false

  import Mox
  import Ysc.AccountsFixtures
  import Ysc.MerchFixtures

  alias Ysc.Merch.{Order, Orders, StripeService}
  alias Ysc.StripeMock

  setup :verify_on_exit!

  setup do
    original = Application.get_env(:ysc, :stripe_client)
    Application.put_env(:ysc, :stripe_client, StripeMock)
    on_exit(fn -> Application.put_env(:ysc, :stripe_client, original) end)

    user =
      user_fixture()
      |> Ecto.Changeset.change(stripe_id: "cus_merch_test")
      |> Repo.update!()

    lines =
      cart_lines_fixture(user, [
        {variant_fixture(nil, %{retail_price: Money.new(:USD, "25")}), 2}
      ])

    {:ok, order} =
      Orders.create_pending_purchase(
        user,
        lines,
        shipping_address_fixture(),
        shipping_option_fixture()
      )

    %{user: user, order: order}
  end

  describe "ensure_payment_intent/2" do
    test "creates an Intent for the order total with identifying metadata", %{
      order: order,
      user: user
    } do
      expect(StripeMock, :create_payment_intent, fn params, opts ->
        # 2 x 25.00 + 5.95 shipping
        assert params.amount == 5595
        assert params.currency == "usd"
        assert params.customer == "cus_merch_test"
        assert params.metadata.merch_order_id == order.id
        assert params.metadata.merch_order_reference == order.reference_id
        assert params.metadata.user_id == user.id
        assert params.description == "Merch - Order #{order.reference_id}"

        assert opts[:headers]["Idempotency-Key"] ==
                 "merch_order_#{order.reference_id}_5595"

        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_new",
           status: "requires_payment_method",
           amount: params.amount,
           client_secret: "pi_new_secret"
         }}
      end)

      assert {:ok, %{id: "pi_new"}} =
               StripeService.ensure_payment_intent(order, user)

      assert %Order{payment_intent_id: "pi_new"} = Orders.get_order!(order.id)
    end

    test "reuses the order's open Intent instead of creating another", %{
      order: order,
      user: user
    } do
      {:ok, order} = Orders.attach_payment_intent(order, "pi_existing")

      expect(StripeMock, :retrieve_payment_intent, fn "pi_existing", _ ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_existing",
           status: "requires_payment_method",
           amount: 5595
         }}
      end)

      assert {:ok, %{id: "pi_existing"}} =
               StripeService.ensure_payment_intent(order, user)
    end

    test "returns an already-paid Intent so the caller can finalize", %{
      order: order,
      user: user
    } do
      {:ok, order} = Orders.attach_payment_intent(order, "pi_paid")

      expect(StripeMock, :retrieve_payment_intent, fn "pi_paid", _ ->
        {:ok,
         %Stripe.PaymentIntent{id: "pi_paid", status: "succeeded", amount: 5595}}
      end)

      assert {:ok, %{status: "succeeded"}} =
               StripeService.ensure_payment_intent(order, user)
    end

    test "reuses a processing Intent instead of minting a second charge", %{
      order: order,
      user: user
    } do
      {:ok, order} = Orders.attach_payment_intent(order, "pi_processing")

      expect(StripeMock, :retrieve_payment_intent, fn "pi_processing", _ ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_processing",
           status: "processing",
           amount: 5595
         }}
      end)

      assert {:ok, %{id: "pi_processing", status: "processing"}} =
               StripeService.ensure_payment_intent(order, user)

      assert Orders.get_order!(order.id).payment_intent_id == "pi_processing"
    end

    test "reuses a requires_action Intent instead of minting a second charge",
         %{
           order: order,
           user: user
         } do
      {:ok, order} = Orders.attach_payment_intent(order, "pi_3ds")

      expect(StripeMock, :retrieve_payment_intent, fn "pi_3ds", _ ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_3ds",
           status: "requires_action",
           amount: 5595
         }}
      end)

      assert {:ok, %{id: "pi_3ds", status: "requires_action"}} =
               StripeService.ensure_payment_intent(order, user)

      assert Orders.get_order!(order.id).payment_intent_id == "pi_3ds"
    end

    test "keeps a processing Intent when a stale-amount replace is refused", %{
      order: order,
      user: user
    } do
      {:ok, order} = Orders.attach_payment_intent(order, "pi_processing_stale")

      expect(StripeMock, :retrieve_payment_intent, fn "pi_processing_stale",
                                                      _ ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_processing_stale",
           status: "processing",
           amount: 100
         }}
      end)

      expect(StripeMock, :cancel_payment_intent, fn "pi_processing_stale", _ ->
        {:error,
         %Stripe.Error{
           source: :stripe,
           code: :invalid_request_error,
           message:
             "You cannot cancel this PaymentIntent because it has a status of processing."
         }}
      end)

      expect(StripeMock, :retrieve_payment_intent, fn "pi_processing_stale",
                                                      opts ->
        assert opts[:expand] == ["latest_charge"]

        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_processing_stale",
           status: "processing",
           amount: 100
         }}
      end)

      assert {:ok, %{id: "pi_processing_stale", status: "processing"}} =
               StripeService.ensure_payment_intent(order, user)

      assert Orders.get_order!(order.id).payment_intent_id ==
               "pi_processing_stale"
    end

    test "replaces a canceled Intent", %{
      order: order,
      user: user
    } do
      {:ok, order} = Orders.attach_payment_intent(order, "pi_old")

      expect(StripeMock, :retrieve_payment_intent, fn "pi_old", _ ->
        {:ok,
         %Stripe.PaymentIntent{id: "pi_old", status: "canceled", amount: 5595}}
      end)

      expect(StripeMock, :create_payment_intent, fn params, _ ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_replacement",
           status: "requires_payment_method",
           amount: params.amount
         }}
      end)

      assert {:ok, %{id: "pi_replacement"}} =
               StripeService.ensure_payment_intent(order, user)

      assert Orders.get_order!(order.id).payment_intent_id == "pi_replacement"
    end

    test "Stripe-cancels a stale-amount Intent before minting a replacement", %{
      order: order,
      user: user
    } do
      {:ok, order} = Orders.attach_payment_intent(order, "pi_stale_amount")

      expect(StripeMock, :retrieve_payment_intent, fn "pi_stale_amount", _ ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_stale_amount",
           status: "requires_payment_method",
           amount: 100
         }}
      end)

      expect(StripeMock, :cancel_payment_intent, fn "pi_stale_amount", _ ->
        {:ok, %Stripe.PaymentIntent{id: "pi_stale_amount", status: "canceled"}}
      end)

      expect(StripeMock, :create_payment_intent, fn params, _ ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_fresh",
           status: "requires_payment_method",
           amount: params.amount
         }}
      end)

      assert {:ok, %{id: "pi_fresh"}} =
               StripeService.ensure_payment_intent(order, user)

      assert Orders.get_order!(order.id).payment_intent_id == "pi_fresh"
    end

    test "returns an already-succeeded Intent when replace cancel reveals capture",
         %{
           order: order,
           user: user
         } do
      {:ok, order} = Orders.attach_payment_intent(order, "pi_race")

      expect(StripeMock, :retrieve_payment_intent, fn "pi_race", _ ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_race",
           status: "requires_payment_method",
           amount: 100
         }}
      end)

      expect(StripeMock, :cancel_payment_intent, fn "pi_race", _ ->
        {:error,
         %Stripe.Error{
           source: :stripe,
           code: :invalid_request_error,
           message:
             "You cannot cancel this PaymentIntent because it has a status of succeeded."
         }}
      end)

      expect(StripeMock, :retrieve_payment_intent, fn "pi_race", opts ->
        assert opts[:expand] == ["latest_charge"]

        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_race",
           status: "succeeded",
           amount: 5595,
           latest_charge: %Stripe.Charge{
             id: "ch_race",
             refunded: false,
             amount: 5595,
             amount_refunded: 0
           }
         }}
      end)

      assert {:ok, %{id: "pi_race", status: "succeeded"}} =
               StripeService.ensure_payment_intent(order, user)

      assert Orders.get_order!(order.id).payment_intent_id == "pi_race"
    end

    test "rejects an Intent Stripe returns with the wrong amount", %{
      order: order,
      user: user
    } do
      expect(StripeMock, :create_payment_intent, fn _, _ ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_stale",
           status: "requires_payment_method",
           amount: 1
         }}
      end)

      assert {:error, message} =
               StripeService.ensure_payment_intent(order, user)

      assert is_binary(message)
      assert Orders.get_order!(order.id).payment_intent_id == nil
    end

    test "surfaces Stripe errors as member-safe text", %{
      order: order,
      user: user
    } do
      expect(StripeMock, :create_payment_intent, fn _, _ ->
        {:error,
         %Stripe.Error{source: :stripe, code: :api_error, message: "boom"}}
      end)

      assert {:error, message} =
               StripeService.ensure_payment_intent(order, user)

      assert is_binary(message)
      refute message =~ "boom"
    end

    test "only pending purchases can be paid", %{order: order, user: user} do
      for status <- [:paid, :submitted, :canceled, :failed] do
        paid = %{order | status: status}

        assert {:error, :not_payable} =
                 StripeService.ensure_payment_intent(paid, user)
      end

      comp = %{order | kind: :admin_comp}

      assert {:error, :not_payable} =
               StripeService.ensure_payment_intent(comp, user)

      free = %{order | total_amount: Money.new(:USD, 0)}

      assert {:error, :not_payable} =
               StripeService.ensure_payment_intent(free, user)
    end
  end

  describe "cancel_payment_intent/1" do
    test "reports a clean cancel" do
      expect(StripeMock, :cancel_payment_intent, fn "pi_1", _ ->
        {:ok, %Stripe.PaymentIntent{id: "pi_1", status: "canceled"}}
      end)

      assert {:ok, :canceled} = StripeService.cancel_payment_intent("pi_1")
    end

    test "reports when the member actually paid" do
      expect(StripeMock, :cancel_payment_intent, fn "pi_2", _ ->
        {:error,
         %Stripe.Error{
           source: :stripe,
           code: :invalid_request_error,
           message:
             "You cannot cancel this PaymentIntent because it has a status of succeeded."
         }}
      end)

      assert {:ok, :succeeded} = StripeService.cancel_payment_intent("pi_2")
    end

    test "treats an already-canceled Intent as canceled" do
      expect(StripeMock, :cancel_payment_intent, fn "pi_3", _ ->
        {:error,
         %Stripe.Error{
           source: :stripe,
           code: :invalid_request_error,
           message: "PaymentIntent was already canceled"
         }}
      end)

      assert {:ok, :canceled} = StripeService.cancel_payment_intent("pi_3")
    end

    test "passes other errors through" do
      expect(StripeMock, :cancel_payment_intent, fn _, _ ->
        {:error,
         %Stripe.Error{source: :stripe, code: :api_error, message: "down"}}
      end)

      assert {:error, %Stripe.Error{}} =
               StripeService.cancel_payment_intent("pi_4")
    end
  end
end
