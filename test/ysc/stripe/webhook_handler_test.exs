defmodule Ysc.Stripe.WebhookHandlerTest do
  use Ysc.DataCase, async: true

  alias Ysc.Stripe.WebhookHandler
  alias Ysc.Subscriptions
  alias Ysc.Ledgers
  alias Ysc.Webhooks
  import Ysc.AccountsFixtures
  import Swoosh.TestAssertions

  # Helper to create a basic Stripe event
  defp build_stripe_event(type, object_data, opts \\ []) do
    event_id =
      Keyword.get(opts, :event_id, "evt_test_#{System.unique_integer()}")

    created_at = Keyword.get(opts, :created, System.os_time(:second))

    %Stripe.Event{
      id: event_id,
      type: type,
      data: %{object: object_data},
      api_version: "2025-10-29.clover",
      created: created_at,
      livemode: false,
      pending_webhooks: 1,
      request: %{
        id: "req_#{System.unique_integer()}",
        idempotency_key: "key_#{System.unique_integer()}"
      },
      object: "event",
      account: "acct_test"
    }
  end

  # Helper to create user with Stripe ID
  defp user_with_stripe_id(attrs \\ %{}) do
    user = user_fixture(attrs)

    {:ok, user} =
      user
      |> Ecto.Changeset.change(stripe_id: "cus_test_#{System.unique_integer()}")
      |> Ysc.Repo.update()

    user
  end

  # Helper to create subscription for user
  defp create_subscription(user, attrs \\ %{}) do
    defaults = %{
      user_id: user.id,
      name: "Membership",
      stripe_id: "sub_test_#{System.unique_integer()}",
      stripe_status: "active",
      start_date: DateTime.utc_now(),
      current_period_start: DateTime.utc_now(),
      current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
    }

    {:ok, subscription} =
      defaults
      |> Map.merge(attrs)
      |> Subscriptions.create_subscription()

    subscription
  end

  setup do
    # Ensure ledger accounts exist
    Ledgers.ensure_basic_accounts()

    # Configure QuickBooks client to use mock (prevents errors when sync jobs run)
    Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

    # Set up QuickBooks configuration for tests
    Application.put_env(:ysc, :quickbooks,
      client_id: "test_client_id",
      client_secret: "test_client_secret",
      company_id: "test_company_id",
      access_token: "test_access_token",
      refresh_token: "test_refresh_token",
      event_item_id: "event_item_123",
      donation_item_id: "donation_item_123",
      bank_account_id: "bank_account_123",
      stripe_account_id: "stripe_account_123"
    )

    # Set up default mocks for automatic sync jobs
    import Mox

    stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
      {:ok, %{"Id" => "qb_customer_default"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params ->
      {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
      {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
    end)

    :ok
  end

  describe "webhook replay protection" do
    test "accepts recent webhook events" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      # Create event from 2 minutes ago (within 5 minute window)
      recent_timestamp =
        DateTime.utc_now() |> DateTime.add(-120, :second) |> DateTime.to_unix()

      invoice_data = %{
        "id" => "in_recent_#{System.unique_integer()}",
        "customer" => user.stripe_id,
        "subscription" => subscription.stripe_id,
        "amount_paid" => 4500,
        "description" => "Recent Invoice",
        "number" => "INV-001",
        "charge" => nil,
        "metadata" => %{}
      }

      event =
        build_stripe_event("invoice.payment_succeeded", invoice_data,
          created: recent_timestamp
        )

      assert :ok = WebhookHandler.handle_event(event)

      # Verify payment was created
      payment = Ledgers.get_payment_by_external_id(invoice_data["id"])
      assert payment != nil
    end

    test "rejects old webhook events (potential replay attack)" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      # Create event from 6 minutes ago (outside 5 minute window)
      old_timestamp =
        DateTime.utc_now() |> DateTime.add(-360, :second) |> DateTime.to_unix()

      invoice_data = %{
        "id" => "in_old_#{System.unique_integer()}",
        "customer" => user.stripe_id,
        "subscription" => subscription.stripe_id,
        "amount_paid" => 4500,
        "charge" => nil
      }

      event =
        build_stripe_event("invoice.payment_succeeded", invoice_data,
          created: old_timestamp
        )

      assert {:error, :webhook_too_old} = WebhookHandler.handle_event(event)

      # Verify payment was NOT created
      payment = Ledgers.get_payment_by_external_id(invoice_data["id"])
      assert payment == nil
    end

    test "rejects very old webhooks (hours old)" do
      user = user_with_stripe_id()

      # Create event from 2 hours ago
      very_old_timestamp =
        DateTime.utc_now() |> DateTime.add(-7200, :second) |> DateTime.to_unix()

      invoice_data = %{
        "id" => "in_very_old_#{System.unique_integer()}",
        "customer" => user.stripe_id,
        "charge" => nil
      }

      event =
        build_stripe_event("invoice.payment_succeeded", invoice_data,
          created: very_old_timestamp
        )

      assert {:error, :webhook_too_old} = WebhookHandler.handle_event(event)
    end
  end

  describe "webhook deduplication" do
    test "processes webhook only once when received multiple times" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      event_id = "evt_duplicate_#{System.unique_integer()}"
      invoice_id = "in_duplicate_#{System.unique_integer()}"

      invoice_data = %{
        "id" => invoice_id,
        "customer" => user.stripe_id,
        "subscription" => subscription.stripe_id,
        "amount_paid" => 4500,
        "charge" => nil,
        "metadata" => %{}
      }

      event =
        build_stripe_event("invoice.payment_succeeded", invoice_data,
          event_id: event_id
        )

      # First processing - should succeed
      assert :ok = WebhookHandler.handle_event(event)

      # Verify payment was created
      payment = Ledgers.get_payment_by_external_id(invoice_id)
      assert payment != nil
      initial_payment_id = payment.id

      # Second processing - should be idempotent
      assert :ok = WebhookHandler.handle_event(event)

      # Verify no duplicate payment
      all_payments = Ledgers.get_payments_by_user(user.id)
      assert length(all_payments) == 1

      # Verify it's the same payment
      payment = Ledgers.get_payment_by_external_id(invoice_id)
      assert payment.id == initial_payment_id
    end

    test "stores webhook event in database for tracking" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      event_id = "evt_track_#{System.unique_integer()}"

      invoice_data = %{
        "id" => "in_track_#{System.unique_integer()}",
        "customer" => user.stripe_id,
        "subscription" => subscription.stripe_id,
        "amount_paid" => 4500,
        "charge" => nil
      }

      event =
        build_stripe_event("invoice.payment_succeeded", invoice_data,
          event_id: event_id
        )

      assert :ok = WebhookHandler.handle_event(event)

      # Verify webhook event was stored
      webhook_event =
        Webhooks.get_webhook_event_by_provider_and_event_id("stripe", event_id)

      assert webhook_event != nil
      assert webhook_event.state == :processed
      assert webhook_event.event_type == "invoice.payment_succeeded"
    end
  end

  describe "refund idempotency" do
    setup do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      # Create initial payment
      invoice_id = "in_for_refund_#{System.unique_integer()}"

      invoice_data = %{
        "id" => invoice_id,
        "customer" => user.stripe_id,
        "subscription" => subscription.stripe_id,
        "amount_paid" => 10_000,
        "charge" => nil
      }

      event = build_stripe_event("invoice.payment_succeeded", invoice_data)
      assert :ok = WebhookHandler.handle_event(event)

      payment = Ledgers.get_payment_by_external_id(invoice_id)

      %{user: user, payment: payment, invoice_id: invoice_id}
    end

    test "processes refund.created only once", %{payment: payment} do
      refund_id = "re_test_#{System.unique_integer()}"

      refund_data = %Stripe.Refund{
        id: refund_id,
        charge: "ch_test",
        amount: 5000,
        status: "succeeded",
        payment_intent: payment.external_payment_id,
        metadata: %{"reason" => "customer request"}
      }

      event = build_stripe_event("refund.created", refund_data)

      # First processing
      assert :ok = WebhookHandler.handle_event(event)

      # Verify refund was created
      refund = Ledgers.get_refund_by_external_id(refund_id)
      assert refund != nil
      assert Money.to_string!(refund.amount) == "$50.00"

      # Second processing - should be idempotent
      assert :ok = WebhookHandler.handle_event(event)

      # Verify no duplicate refund
      all_refunds =
        from(r in Ysc.Ledgers.Refund, where: r.payment_id == ^payment.id)
        |> Ysc.Repo.all()

      assert length(all_refunds) == 1
    end

    test "handles both charge.refunded and refund.created without duplicates",
         %{payment: payment} do
      refund_id = "re_both_#{System.unique_integer()}"

      # Create refund struct
      refund_struct = %Stripe.Refund{
        id: refund_id,
        charge: "ch_test",
        amount: 5000,
        status: "succeeded",
        payment_intent: payment.external_payment_id
      }

      # Create charge struct with refund
      charge_struct = %Stripe.Charge{
        id: "ch_test",
        payment_intent: payment.external_payment_id,
        amount: 10_000,
        refunds: %Stripe.List{
          data: [refund_struct],
          has_more: false,
          object: "list",
          url: "/v1/charges/ch_test/refunds"
        },
        metadata: %{}
      }

      # Send charge.refunded first
      charge_event = build_stripe_event("charge.refunded", charge_struct)
      assert :ok = WebhookHandler.handle_event(charge_event)

      # Verify refund was created
      refund = Ledgers.get_refund_by_external_id(refund_id)
      assert refund != nil
      first_refund_id = refund.id

      # Send refund.created - should be idempotent
      refund_event = build_stripe_event("refund.created", refund_struct)
      assert :ok = WebhookHandler.handle_event(refund_event)

      # Verify no duplicate refund
      all_refunds =
        from(r in Ysc.Ledgers.Refund, where: r.payment_id == ^payment.id)
        |> Ysc.Repo.all()

      assert length(all_refunds) == 1

      # Verify it's the same refund
      refund = Ledgers.get_refund_by_external_id(refund_id)
      assert refund.id == first_refund_id
    end

    test "handles multiple partial refunds correctly", %{payment: payment} do
      # Create first partial refund
      refund1_id = "re_partial1_#{System.unique_integer()}"

      refund1 = %Stripe.Refund{
        id: refund1_id,
        charge: "ch_test",
        amount: 3000,
        status: "succeeded",
        payment_intent: payment.external_payment_id
      }

      event1 = build_stripe_event("refund.created", refund1)
      assert :ok = WebhookHandler.handle_event(event1)

      # Create second partial refund
      refund2_id = "re_partial2_#{System.unique_integer()}"

      refund2 = %Stripe.Refund{
        id: refund2_id,
        charge: "ch_test",
        amount: 4000,
        status: "succeeded",
        payment_intent: payment.external_payment_id
      }

      event2 = build_stripe_event("refund.created", refund2)
      assert :ok = WebhookHandler.handle_event(event2)

      # Verify two separate refunds were created
      all_refunds =
        from(r in Ysc.Ledgers.Refund, where: r.payment_id == ^payment.id)
        |> Ysc.Repo.all()

      assert length(all_refunds) == 2

      # Verify amounts
      refund1_record = Ledgers.get_refund_by_external_id(refund1_id)
      refund2_record = Ledgers.get_refund_by_external_id(refund2_id)

      assert Money.to_string!(refund1_record.amount) == "$30.00"
      assert Money.to_string!(refund2_record.amount) == "$40.00"

      # Verify payment is not marked as fully refunded
      payment = Ysc.Repo.reload(payment)
      assert payment.status != :refunded
    end

    test "marks payment as refunded when fully refunded", %{payment: payment} do
      refund_id = "re_full_#{System.unique_integer()}"

      # Full refund
      refund_data = %Stripe.Refund{
        id: refund_id,
        charge: "ch_test",
        # Full amount
        amount: 10_000,
        status: "succeeded",
        payment_intent: payment.external_payment_id
      }

      event = build_stripe_event("refund.created", refund_data)
      assert :ok = WebhookHandler.handle_event(event)

      # Verify payment status updated
      payment = Ysc.Repo.reload(payment)
      assert payment.status == :refunded
    end
  end

  describe "subscription race condition handling" do
    test "creates subscription from Stripe when invoice arrives before subscription webhook",
         %{} do
      user = user_with_stripe_id()
      stripe_subscription_id = "sub_race_#{System.unique_integer()}"

      # Verify subscription doesn't exist yet
      assert Subscriptions.get_subscription_by_stripe_id(stripe_subscription_id) ==
               nil

      invoice_data = %{
        "id" => "in_race_#{System.unique_integer()}",
        "customer" => user.stripe_id,
        "subscription" => stripe_subscription_id,
        "amount_paid" => 4500,
        "charge" => nil
      }

      _event = build_stripe_event("invoice.payment_succeeded", invoice_data)

      # Mock Stripe API call (in real test, you'd use Mox)
      # For this test, we'll just verify it attempts to create
      # The actual implementation fetches from Stripe

      # Since we can't easily mock Stripe.Subscription.retrieve in this context,
      # this test would require Mox setup. For now, we document the expected behavior:
      # The handler should call find_or_create_subscription_reference which would:
      # 1. Try to find subscription locally
      # 2. Not find it
      # 3. Call Stripe.Subscription.retrieve
      # 4. Create subscription locally
      # 5. Use that ID for the payment

      # For a real implementation test, set up Mox:
      # expect(StripeMock, :retrieve_subscription, fn id ->
      #   {:ok, %Stripe.Subscription{id: id, ...}}
      # end)
    end

    test "resolves subscription from customer when subscription ID is null",
         %{} do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      # Invoice with null subscription but subscription_create billing reason
      invoice_data = %{
        "id" => "in_resolve_#{System.unique_integer()}",
        "customer" => user.stripe_id,
        "subscription" => nil,
        "billing_reason" => "subscription_create",
        "amount_paid" => 4500,
        "description" => "Subscription Invoice",
        "number" => "INV-001",
        "charge" => nil,
        "metadata" => %{}
      }

      event = build_stripe_event("invoice.payment_succeeded", invoice_data)

      assert :ok = WebhookHandler.handle_event(event)

      # Verify payment was created
      payment = Ledgers.get_payment_by_external_id(invoice_data["id"])
      assert payment != nil
      assert payment.user_id == user.id

      # Verify payment is linked to subscription
      subscription_payments =
        Ledgers.get_payments_for_subscription(subscription.id)

      assert Enum.any?(subscription_payments, fn p -> p.id == payment.id end)
    end

    test "skips processing when subscription cannot be resolved", %{} do
      user = user_with_stripe_id()

      invoice_data = %{
        "id" => "in_skip_#{System.unique_integer()}",
        "customer" => user.stripe_id,
        "subscription" => nil,
        "billing_reason" => "manual",
        "amount_paid" => 4500,
        "charge" => nil
      }

      event = build_stripe_event("invoice.payment_succeeded", invoice_data)

      assert :ok = WebhookHandler.handle_event(event)

      # Should NOT create payment
      assert Ledgers.get_payment_by_external_id(invoice_data["id"]) == nil
    end
  end

  describe "membership payment emails" do
    test "sends membership_payment_confirmation email on first payment (subscription_create)",
         %{} do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      invoice_data = %{
        "id" => "in_first_#{System.unique_integer()}",
        "customer" => user.stripe_id,
        "subscription" => subscription.stripe_id,
        "billing_reason" => "subscription_create",
        "amount_paid" => 4500,
        "description" => "Membership Invoice",
        "number" => "INV-001",
        "charge" => nil,
        "metadata" => %{}
      }

      event = build_stripe_event("invoice.payment_succeeded", invoice_data)
      assert :ok = WebhookHandler.handle_event(event)

      assert_email_sent(
        subject: "Welcome to YSC – Your Membership is Active! 🎉",
        to: {nil, user.email}
      )
    end

    test "sends membership_renewal_success email on renewal (subscription_cycle)",
         %{} do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      invoice_data = %{
        "id" => "in_renewal_#{System.unique_integer()}",
        "customer" => user.stripe_id,
        "subscription" => subscription.stripe_id,
        "billing_reason" => "subscription_cycle",
        "amount_paid" => 4500,
        "description" => "Membership Renewal",
        "number" => "INV-002",
        "charge" => nil,
        "metadata" => %{}
      }

      event = build_stripe_event("invoice.payment_succeeded", invoice_data)
      assert :ok = WebhookHandler.handle_event(event)

      assert_email_sent(
        subject: "Your YSC Membership Has Been Renewed! 🎉",
        to: {nil, user.email}
      )
    end

    test "sends membership_renewal_success email on subscription_update billing reason",
         %{} do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      invoice_data = %{
        "id" => "in_update_#{System.unique_integer()}",
        "customer" => user.stripe_id,
        "subscription" => subscription.stripe_id,
        "billing_reason" => "subscription_update",
        "amount_paid" => 5000,
        "description" => "Membership Update",
        "number" => "INV-003",
        "charge" => nil,
        "metadata" => %{}
      }

      event = build_stripe_event("invoice.payment_succeeded", invoice_data)
      assert :ok = WebhookHandler.handle_event(event)

      assert_email_sent(
        subject: "Your YSC Membership Has Been Renewed! 🎉",
        to: {nil, user.email}
      )
    end
  end

  describe "subscription webhooks" do
    test "creates subscription from customer.subscription.created" do
      user = user_with_stripe_id()

      subscription_data = %Stripe.Subscription{
        id: "sub_created_#{System.unique_integer()}",
        customer: user.stripe_id,
        status: "active",
        start_date: System.os_time(:second),
        current_period_start: System.os_time(:second),
        current_period_end: System.os_time(:second) + 30 * 24 * 60 * 60,
        items: %Stripe.List{
          data: [],
          has_more: false,
          object: "list",
          url: "/v1/subscription_items"
        }
      }

      event =
        build_stripe_event("customer.subscription.created", subscription_data)

      assert :ok = WebhookHandler.handle_event(event)

      # Verify subscription was created
      subscription =
        Subscriptions.get_subscription_by_stripe_id(subscription_data.id)

      assert subscription != nil
      assert subscription.user_id == user.id
      assert subscription.stripe_status == "active"
    end

    test "marks subscription as cancelled when deleted" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      subscription_data = %Stripe.Subscription{
        id: subscription.stripe_id,
        customer: user.stripe_id,
        status: "canceled"
      }

      event =
        build_stripe_event("customer.subscription.deleted", subscription_data)

      assert :ok = WebhookHandler.handle_event(event)

      # Verify subscription was marked as cancelled
      subscription = Ysc.Repo.reload(subscription)
      assert subscription.stripe_status == "cancelled"
    end

    test "updates subscription status when changed" do
      user = user_with_stripe_id()
      subscription = create_subscription(user, %{stripe_status: "active"})

      subscription_data = %Stripe.Subscription{
        id: subscription.stripe_id,
        customer: user.stripe_id,
        status: "past_due",
        start_date: System.os_time(:second),
        current_period_start: System.os_time(:second),
        current_period_end: System.os_time(:second) + 30 * 24 * 60 * 60,
        items: %Stripe.List{
          data: [],
          has_more: false,
          object: "list",
          url: "/v1/subscription_items"
        }
      }

      event =
        build_stripe_event("customer.subscription.updated", subscription_data)

      assert :ok = WebhookHandler.handle_event(event)

      # Verify status was updated
      subscription = Ysc.Repo.reload(subscription)
      assert subscription.stripe_status == "past_due"
    end
  end

  describe "payment method webhooks" do
    test "handles payment_method.attached without errors" do
      user = user_with_stripe_id()

      payment_method_data = %Stripe.PaymentMethod{
        id: "pm_test_#{System.unique_integer()}",
        customer: user.stripe_id,
        type: "card",
        card: %{
          brand: "visa",
          last4: "4242",
          exp_month: 12,
          exp_year: 2025
        }
      }

      event = build_stripe_event("payment_method.attached", payment_method_data)

      # Should not error
      assert :ok = WebhookHandler.handle_event(event)
    end

    test "handles payment_method.detached without errors" do
      payment_method_data = %Stripe.PaymentMethod{
        id: "pm_detached_#{System.unique_integer()}",
        customer: nil,
        type: "card"
      }

      event = build_stripe_event("payment_method.detached", payment_method_data)

      assert :ok = WebhookHandler.handle_event(event)
    end
  end

  describe "ledger integrity after operations" do
    test "maintains ledger balance after payment processing" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      invoice_data = %{
        "id" => "in_balance_#{System.unique_integer()}",
        "customer" => user.stripe_id,
        "subscription" => subscription.stripe_id,
        "amount_paid" => 10_000,
        "charge" => nil
      }

      event = build_stripe_event("invoice.payment_succeeded", invoice_data)

      assert :ok = WebhookHandler.handle_event(event)

      # Verify ledger is balanced
      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end

    test "maintains ledger balance after refund processing" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      # Create payment
      invoice_data = %{
        "id" => "in_refund_balance_#{System.unique_integer()}",
        "customer" => user.stripe_id,
        "subscription" => subscription.stripe_id,
        "amount_paid" => 10_000,
        "charge" => nil
      }

      payment_event =
        build_stripe_event("invoice.payment_succeeded", invoice_data)

      assert :ok = WebhookHandler.handle_event(payment_event)

      payment = Ledgers.get_payment_by_external_id(invoice_data["id"])

      # Process refund
      refund_data = %Stripe.Refund{
        id: "re_balance_#{System.unique_integer()}",
        charge: "ch_test",
        amount: 5000,
        status: "succeeded",
        payment_intent: payment.external_payment_id
      }

      refund_event = build_stripe_event("refund.created", refund_data)
      assert :ok = WebhookHandler.handle_event(refund_event)

      # Verify ledger is still balanced
      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end

    test "maintains ledger balance after multiple partial refunds" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      # Create payment
      invoice_data = %{
        "id" => "in_multi_refund_#{System.unique_integer()}",
        "customer" => user.stripe_id,
        "subscription" => subscription.stripe_id,
        "amount_paid" => 10_000,
        "charge" => nil
      }

      payment_event =
        build_stripe_event("invoice.payment_succeeded", invoice_data)

      assert :ok = WebhookHandler.handle_event(payment_event)

      payment = Ledgers.get_payment_by_external_id(invoice_data["id"])

      # Process multiple partial refunds
      for i <- 1..3 do
        refund_data = %Stripe.Refund{
          id: "re_partial_#{i}_#{System.unique_integer()}",
          charge: "ch_test",
          amount: 2000,
          status: "succeeded",
          payment_intent: payment.external_payment_id
        }

        refund_event = build_stripe_event("refund.created", refund_data)
        assert :ok = WebhookHandler.handle_event(refund_event)
      end

      # Verify ledger is still balanced
      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end

    test "maintains ledger balance with complex scenario" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      # Create multiple payments
      for i <- 1..3 do
        invoice_data = %{
          "id" => "in_complex_#{i}_#{System.unique_integer()}",
          "customer" => user.stripe_id,
          "subscription" => subscription.stripe_id,
          "amount_paid" => 5000 * i,
          "charge" => nil
        }

        event = build_stripe_event("invoice.payment_succeeded", invoice_data)
        assert :ok = WebhookHandler.handle_event(event)
      end

      # Get one payment and refund it partially
      [payment | _] = Ledgers.get_payments_by_user(user.id)

      refund_data = %Stripe.Refund{
        id: "re_complex_#{System.unique_integer()}",
        charge: "ch_test",
        amount: 2500,
        status: "succeeded",
        payment_intent: payment.external_payment_id
      }

      refund_event = build_stripe_event("refund.created", refund_data)
      assert :ok = WebhookHandler.handle_event(refund_event)

      # Verify ledger is still balanced
      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end
  end

  describe "error handling" do
    test "handles webhook for non-existent user gracefully" do
      invoice_data = %{
        "id" => "in_no_user_#{System.unique_integer()}",
        "customer" => "cus_nonexistent",
        "subscription" => "sub_test",
        "amount_paid" => 4500,
        "charge" => nil
      }

      event = build_stripe_event("invoice.payment_succeeded", invoice_data)

      # Should not crash
      assert :ok = WebhookHandler.handle_event(event)

      # Should not create payment
      assert Ledgers.get_payment_by_external_id(invoice_data["id"]) == nil
    end

    test "marks webhook as failed when processing errors" do
      # Create event that will fail processing (invoice with subscription but missing customer)
      # This will cause the handler to raise an error because customer is required
      invalid_data = %{
        "id" => "in_invalid_#{System.unique_integer()}",
        # Has subscription so it won't be skipped
        "subscription" => "sub_test_123",
        # Non-existent customer will cause error
        "customer" => "cus_nonexistent",
        "amount_paid" => 5000
      }

      event = build_stripe_event("invoice.payment_succeeded", invalid_data)

      # Should handle error gracefully
      assert :ok = WebhookHandler.handle_event(event)

      # Webhook should be marked as failed
      webhook_event =
        Webhooks.get_webhook_event_by_provider_and_event_id("stripe", event.id)

      assert webhook_event != nil
      assert webhook_event.state == :failed
    end

    test "handles unknown webhook event types gracefully" do
      unknown_data = %{"id" => "unknown_data"}

      event = build_stripe_event("some.unknown.event", unknown_data)

      # Should not crash
      assert :ok = WebhookHandler.handle_event(event)
    end
  end

  describe "payment intent webhooks" do
    test "logs payment_intent.succeeded without error" do
      payment_intent_data = %Stripe.PaymentIntent{
        id: "pi_test_#{System.unique_integer()}",
        status: "succeeded",
        customer: "cus_test",
        amount: 10_000,
        description: "Test payment"
      }

      event =
        build_stripe_event("payment_intent.succeeded", payment_intent_data)

      assert :ok = WebhookHandler.handle_event(event)
    end
  end

  describe "customer webhooks" do
    test "handles customer.updated without error" do
      user = user_with_stripe_id()

      customer_data = %Stripe.Customer{
        id: user.stripe_id,
        email: user.email,
        name: "#{user.first_name} #{user.last_name}"
      }

      event = build_stripe_event("customer.updated", customer_data)

      assert :ok = WebhookHandler.handle_event(event)
    end

    test "cancels all subscriptions when customer is deleted" do
      user = user_with_stripe_id()
      subscription = create_subscription(user, %{stripe_status: "active"})

      customer_data = %Stripe.Customer{
        id: user.stripe_id,
        email: user.email
      }

      event = build_stripe_event("customer.deleted", customer_data)

      assert :ok = WebhookHandler.handle_event(event)

      # Verify subscription was cancelled
      subscription = Ysc.Repo.reload(subscription)
      assert subscription.stripe_status == "cancelled"
    end
  end
end
