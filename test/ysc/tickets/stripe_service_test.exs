defmodule Ysc.Tickets.StripeServiceTest do
  @moduledoc """
  Tests for Ysc.Tickets.StripeService module.
  """
  use Ysc.DataCase, async: true

  import Mox
  alias Ysc.Tickets.StripeService
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  setup :verify_on_exit!

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    user = user_fixture()

    # Give user lifetime membership
    user =
      user
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Ysc.Repo.update!()

    event = event_fixture()
    tier = ticket_tier_fixture(%{event_id: event.id})

    ticket_selections = %{tier.id => 1}

    {:ok, ticket_order} =
      Ysc.Tickets.create_ticket_order(user.id, event.id, ticket_selections)

    # Configure Stripe client mock
    Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

    %{user: user, ticket_order: ticket_order}
  end

  describe "create_payment_intent/2" do
    test "creates payment intent with correct parameters", %{
      ticket_order: ticket_order
    } do
      expect(Ysc.StripeMock, :create_payment_intent, fn params, _opts ->
        # $50.00 in cents
        assert params.amount == 5000
        assert params.currency == "usd"
        # Metadata uses atom keys in the code
        assert params.metadata[:ticket_order_id] == ticket_order.id
        {:ok, %{id: "pi_test_123", status: "requires_payment_method"}}
      end)

      assert {:ok, payment_intent} =
               StripeService.create_payment_intent(ticket_order)

      assert payment_intent.id == "pi_test_123"
    end

    test "includes customer_id when provided", %{ticket_order: ticket_order} do
      expect(Ysc.StripeMock, :create_payment_intent, fn params, _opts ->
        assert params.customer == "cus_test_123"
        {:ok, %{id: "pi_test_123", status: "requires_payment_method"}}
      end)

      assert {:ok, _} =
               StripeService.create_payment_intent(ticket_order,
                 customer_id: "cus_test_123"
               )
    end

    test "handles Stripe errors gracefully", %{ticket_order: ticket_order} do
      expect(Ysc.StripeMock, :create_payment_intent, fn _params, _opts ->
        {:error,
         %Stripe.Error{
           message: "Card declined",
           source: :api,
           code: "card_declined"
         }}
      end)

      assert {:error, "Card declined"} =
               StripeService.create_payment_intent(ticket_order)
    end
  end

  describe "cancel_payment_intent/1" do
    test "cancels payment intent successfully" do
      expect(Ysc.StripeMock, :cancel_payment_intent, fn _id, _opts ->
        {:ok, %{id: "pi_test_123", status: "canceled"}}
      end)

      assert :ok = StripeService.cancel_payment_intent("pi_test_123")
    end

    test "handles already canceled payment intent" do
      expect(Ysc.StripeMock, :cancel_payment_intent, fn _id, _opts ->
        {:error,
         %Stripe.Error{
           message: "PaymentIntent already canceled",
           source: :api,
           code: "payment_intent_already_canceled"
         }}
      end)

      assert :ok = StripeService.cancel_payment_intent("pi_test_123")
    end

    test "returns error for other Stripe errors" do
      expect(Ysc.StripeMock, :cancel_payment_intent, fn _id, _opts ->
        {:error,
         %Stripe.Error{
           message: "Invalid payment intent",
           source: :api,
           code: "invalid_payment_intent"
         }}
      end)

      assert {:error, "Invalid payment intent"} =
               StripeService.cancel_payment_intent("pi_test_123")
    end

    test "returns ok for nil payment intent" do
      assert :ok = StripeService.cancel_payment_intent(nil)
    end
  end
end
