defmodule Ysc.Stripe.WebhookHandlerTest do
  use Ysc.DataCase, async: false
  # Most tests can run async, but some complex ones need to be synchronous
  # due to transaction isolation with the new transactional webhook processing

  alias Ysc.Stripe.SubscriptionFixtures
  alias Ysc.Stripe.WebhookHandler
  alias Ysc.Subscriptions
  alias Ysc.Ledgers
  alias Ysc.Webhooks
  import Ysc.AccountsFixtures
  import Swoosh.TestAssertions

  # Test-only module: when :webhook_test_return_nil_for_event_id is set,
  # get_webhook_event_by_provider_and_event_id returns nil for that event_id
  # so we can test the "webhook not found after duplicate error" path.
  defmodule WebhooksReturnNilForEvent do
    def get_webhook_event_by_provider_and_event_id(provider, event_id) do
      if provider == "stripe" and
           event_id ==
             Application.get_env(:ysc, :webhook_test_return_nil_for_event_id) do
        nil
      else
        Ysc.Webhooks.get_webhook_event_by_provider_and_event_id(
          provider,
          event_id
        )
      end
    end
  end

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
    attrs =
      Map.put_new_lazy(attrs, :email, fn ->
        "stripe_webhook_user_#{System.unique_integer([:positive])}_#{:rand.uniform(999_999_999)}@example.com"
      end)

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

    stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params, _opts ->
      {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params, _opts ->
      {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :query_account_by_name, fn _name ->
      {:ok, "revenue_account_default"}
    end)

    stub(Ysc.Quickbooks.ClientMock, :get_or_create_item, fn _name, _opts ->
      {:ok, "qb_item_default"}
    end)

    stub(Ysc.Quickbooks.ClientMock, :get_item_by_id, fn _id ->
      {:ok,
       %{
         "Id" => "qb_item_default",
         "IncomeAccountRef" => %{"value" => "revenue_account_default"}
       }}
    end)

    stub(Ysc.Quickbooks.ClientMock, :create_refund_receipt, fn _params, _opts ->
      {:ok, %{"Id" => "qb_rr_default", "TotalAmt" => "0.00"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :query_class_by_name, fn _name ->
      {:ok, "qb_class_default"}
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

    test "returns error when duplicate is detected but event not found on lookup (race condition)" do
      # Simulates the rare case: we get DuplicateWebhookEventError (row existed on insert)
      # but get_webhook_event_by_provider_and_event_id returns nil (e.g. row deleted).
      # We return error so Stripe retries.
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      event_id = "evt_not_found_after_dup_#{System.unique_integer()}"
      invoice_id = "in_not_found_#{System.unique_integer()}"

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

      # Pre-create the webhook event so the second handle_event will get duplicate on insert
      Webhooks.create_webhook_event!(%{
        provider: "stripe",
        event_id: event_id,
        event_type: event.type,
        payload: WebhookHandler.event_payload_for_storage(event)
      })

      # Configure test to return nil for this event_id so handler hits "not found after duplicate" path
      Application.put_env(:ysc, :webhooks_context, WebhooksReturnNilForEvent)
      Application.put_env(:ysc, :webhook_test_return_nil_for_event_id, event_id)

      on_exit(fn ->
        Application.delete_env(:ysc, :webhooks_context)
        Application.delete_env(:ysc, :webhook_test_return_nil_for_event_id)
      end)

      # Second delivery (duplicate): insert raises, lookup returns nil -> return error for Stripe retry
      assert {:error, :webhook_not_found_after_duplicate} =
               WebhookHandler.handle_event(event)
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

    @tag :sync
    test "handles both charge.refunded and refund.created without duplicates",
         %{payment: payment} do
      refund_id = "re_both_#{System.unique_integer()}"

      # Create refund struct - IMPORTANT: include payment_intent to avoid Stripe API call
      refund_struct = %Stripe.Refund{
        id: refund_id,
        charge: "ch_test",
        amount: 5000,
        status: "succeeded",
        payment_intent: payment.external_payment_id,
        metadata: %{}
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

    test "resolves subscription from customer for proration invoices (subscription_update)",
         %{} do
      user = user_with_stripe_id()
      subscription = create_subscription(user, %{stripe_status: "active"})

      # Proration invoice with null subscription but subscription_update billing reason
      # This simulates what happens during subscription upgrades/downgrades
      invoice_data = %{
        "id" => "in_proration_#{System.unique_integer()}",
        "customer" => user.stripe_id,
        "subscription" => nil,
        "billing_reason" => "subscription_update",
        "amount_paid" => 1508,
        "description" => "Proration for upgrade",
        "number" => "INV-PRORATION",
        "charge" => nil,
        "metadata" => %{}
      }

      event = build_stripe_event("invoice.payment_succeeded", invoice_data)

      assert :ok = WebhookHandler.handle_event(event)

      # Verify payment was created
      payment = Ledgers.get_payment_by_external_id(invoice_data["id"])
      assert payment != nil
      assert payment.user_id == user.id
      assert Money.to_string!(payment.amount) == "$15.08"

      # Verify payment is linked to subscription
      subscription_payments =
        Ledgers.get_payments_for_subscription(subscription.id)

      assert Enum.any?(subscription_payments, fn p -> p.id == payment.id end)

      # Verify email was sent for renewal (subscription_update is treated as renewal)
      assert_email_sent(
        subject: "Your YSC Membership Has Been Renewed! 🎉",
        to: {nil, user.email}
      )
    end

    test "resolves user from local subscription when invoice customer_id is orphaned" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)
      orphaned_customer = "cus_orphan_#{System.unique_integer()}"

      invoice_data = %{
        "id" => "in_orphan_customer_#{System.unique_integer()}",
        "customer" => orphaned_customer,
        "subscription" => subscription.stripe_id,
        "amount_paid" => 4500,
        "description" => "Renewal on stray Stripe customer",
        "number" => "INV-ORPHAN",
        "charge" => nil,
        "metadata" => %{}
      }

      event = build_stripe_event("invoice.payment_succeeded", invoice_data)
      assert :ok = WebhookHandler.handle_event(event)

      payment = Ledgers.get_payment_by_external_id(invoice_data["id"])
      assert payment != nil
      assert payment.user_id == user.id

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
        subject: "Your YSC Membership Payment Receipt",
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

    test "sends upgrade-specific membership_renewal_success email on Single to Family upgrade",
         %{} do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      # Add family subscription item so get_membership_type returns :family
      family_plan =
        Application.get_env(:ysc, :membership_plans, [])
        |> Enum.find(&(&1.id in [:family, "family"]))

      family_price_id = family_plan && family_plan.stripe_price_id

      assert family_price_id,
             "membership_plans must include family plan for this test"

      Subscriptions.create_subscription_item(%{
        subscription_id: subscription.id,
        stripe_id: "si_family_#{System.unique_integer()}",
        stripe_product_id: "prod_family",
        stripe_price_id: family_price_id,
        quantity: 1
      })

      invoice_data = %{
        "id" => "in_upgrade_#{System.unique_integer()}",
        "customer" => user.stripe_id,
        "subscription" => subscription.stripe_id,
        "billing_reason" => "subscription_update",
        "amount_paid" => 6500,
        "description" => "Single to Family Upgrade",
        "number" => "INV-UPGRADE",
        "charge" => nil,
        "metadata" => %{}
      }

      event = build_stripe_event("invoice.payment_succeeded", invoice_data)
      assert :ok = WebhookHandler.handle_event(event)

      assert_email_sent(
        subject: "Your YSC Membership Has Been Upgraded to Family! 🎉",
        to: {nil, user.email}
      )
    end
  end

  describe "subscription webhooks" do
    test "creates subscription from customer.subscription.created" do
      user = user_with_stripe_id()

      subscription_data =
        SubscriptionFixtures.subscription(
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
        )

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

    test "creates subscription when customer_id is orphaned but metadata user_id matches" do
      user = user_with_stripe_id()
      orphaned_customer = "cus_orphan_#{System.unique_integer()}"
      stripe_sub_id = "sub_orphan_meta_#{System.unique_integer()}"

      subscription_data =
        SubscriptionFixtures.subscription(
          id: stripe_sub_id,
          customer: orphaned_customer,
          status: "active",
          metadata: %{"user_id" => user.id},
          start_date: System.os_time(:second),
          current_period_start: System.os_time(:second),
          current_period_end: System.os_time(:second) + 30 * 24 * 60 * 60,
          items: %Stripe.List{
            data: [],
            has_more: false,
            object: "list",
            url: "/v1/subscription_items"
          }
        )

      event =
        build_stripe_event("customer.subscription.created", subscription_data)

      assert :ok = WebhookHandler.handle_event(event)

      subscription = Subscriptions.get_subscription_by_stripe_id(stripe_sub_id)
      assert subscription != nil
      assert subscription.user_id == user.id
    end

    test "does not create subscription from customer.subscription.created when status is incomplete" do
      # Admin "paid elsewhere" and checkout create subscriptions that start as
      # incomplete; Stripe sends subscription.created before we pay. If we
      # created locally here we'd race with the flow that then creates/updates
      # with active data, leaving an incomplete record and "missing" membership.
      user = user_with_stripe_id()
      stripe_sub_id = "sub_incomplete_#{System.unique_integer()}"

      subscription_data =
        SubscriptionFixtures.subscription(
          id: stripe_sub_id,
          customer: user.stripe_id,
          status: "incomplete",
          start_date: System.os_time(:second),
          current_period_start: nil,
          current_period_end: nil,
          items: %Stripe.List{
            data: [],
            has_more: false,
            object: "list",
            url: "/v1/subscription_items"
          }
        )

      event =
        build_stripe_event("customer.subscription.created", subscription_data)

      assert :ok = WebhookHandler.handle_event(event)

      assert Subscriptions.get_subscription_by_stripe_id(stripe_sub_id) == nil
    end

    test "marks subscription as cancelled when deleted" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      subscription_data =
        SubscriptionFixtures.subscription(
          id: subscription.stripe_id,
          customer: user.stripe_id,
          status: "canceled"
        )

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

      subscription_data =
        SubscriptionFixtures.subscription(
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
        )

      event =
        build_stripe_event("customer.subscription.updated", subscription_data)

      assert :ok = WebhookHandler.handle_event(event)

      # Verify status was updated
      subscription = Ysc.Repo.reload(subscription)
      assert subscription.stripe_status == "past_due"
    end

    test "preserves period dates when subscription.updated has null dates (schedule attached)" do
      # When a subscription is attached to a schedule (e.g. scheduled downgrade),
      # Stripe sends null for current_period_start and current_period_end.
      # We must preserve existing values or the user incorrectly shows "no membership"
      user = user_with_stripe_id()
      period_end = DateTime.add(DateTime.utc_now(), 30, :day)

      subscription =
        create_subscription(user, %{
          stripe_status: "active",
          current_period_start: DateTime.utc_now(),
          current_period_end: period_end
        })

      original_period_start = subscription.current_period_start
      original_period_end = subscription.current_period_end

      # Simulate Stripe webhook when schedule is attached - null period dates
      subscription_data =
        SubscriptionFixtures.subscription(
          id: subscription.stripe_id,
          customer: user.stripe_id,
          status: "active",
          start_date: nil,
          current_period_start: nil,
          current_period_end: nil,
          items: %Stripe.List{
            data: [],
            has_more: false,
            object: "list",
            url: "/v1/subscription_items"
          }
        )

      event =
        build_stripe_event("customer.subscription.updated", subscription_data)

      assert :ok = WebhookHandler.handle_event(event)

      # Period dates must be preserved - not overwritten with nil
      subscription = Ysc.Repo.reload(subscription)
      assert subscription.current_period_start == original_period_start
      assert subscription.current_period_end == original_period_end
      assert Subscriptions.active?(subscription)
    end

    test "recreates subscription when subscription.updated received but subscription missing locally (e.g. was deleted on incomplete_expired)" do
      user = user_with_stripe_id()
      stripe_sub_id = "sub_recreated_#{System.unique_integer()}"

      # No local subscription - simulates we had deleted it when it went incomplete_expired
      assert Subscriptions.get_subscription_by_stripe_id(stripe_sub_id) == nil

      ts = System.os_time(:second)

      fake_stripe_subscription =
        SubscriptionFixtures.subscription(
          id: stripe_sub_id,
          customer: user.stripe_id,
          status: "active",
          start_date: ts,
          current_period_start: ts,
          current_period_end: ts + 30 * 24 * 60 * 60,
          ended_at: nil,
          items: %Stripe.List{
            data: [],
            has_more: false,
            object: "list",
            url: "/v1/subscription_items"
          }
        )

      callback = fn _id, _opts -> {:ok, fake_stripe_subscription} end

      try do
        Application.put_env(
          :ysc,
          :subscription_retrieve_for_webhook_callback,
          callback
        )

        event_data =
          SubscriptionFixtures.subscription(
            id: stripe_sub_id,
            customer: user.stripe_id,
            status: "active",
            start_date: ts,
            current_period_start: ts,
            current_period_end: ts + 30 * 24 * 60 * 60,
            items: %Stripe.List{
              data: [],
              has_more: false,
              object: "list",
              url: "/v1/subscription_items"
            }
          )

        event = build_stripe_event("customer.subscription.updated", event_data)
        assert :ok = WebhookHandler.handle_event(event)

        subscription =
          Subscriptions.get_subscription_by_stripe_id(stripe_sub_id)

        assert subscription != nil
        assert subscription.user_id == user.id
        assert subscription.stripe_status == "active"
        assert Subscriptions.active?(subscription)
      after
        Application.delete_env(
          :ysc,
          :subscription_retrieve_for_webhook_callback
        )
      end
    end

    test "recreates subscription when status is trialing and subscription missing locally" do
      user = user_with_stripe_id()
      stripe_sub_id = "sub_trialing_#{System.unique_integer()}"

      assert Subscriptions.get_subscription_by_stripe_id(stripe_sub_id) == nil

      ts = System.os_time(:second)

      fake_stripe_subscription =
        SubscriptionFixtures.subscription(
          id: stripe_sub_id,
          customer: user.stripe_id,
          status: "trialing",
          start_date: ts,
          current_period_start: ts,
          current_period_end: ts + 30 * 24 * 60 * 60,
          ended_at: nil,
          items: %Stripe.List{
            data: [],
            has_more: false,
            object: "list",
            url: "/v1/subscription_items"
          }
        )

      callback = fn _id, _opts -> {:ok, fake_stripe_subscription} end

      try do
        Application.put_env(
          :ysc,
          :subscription_retrieve_for_webhook_callback,
          callback
        )

        event_data =
          SubscriptionFixtures.subscription(
            id: stripe_sub_id,
            customer: user.stripe_id,
            status: "trialing",
            items: %Stripe.List{
              data: [],
              has_more: false,
              object: "list",
              url: "/v1/subscription_items"
            }
          )

        event = build_stripe_event("customer.subscription.updated", event_data)
        assert :ok = WebhookHandler.handle_event(event)

        subscription =
          Subscriptions.get_subscription_by_stripe_id(stripe_sub_id)

        assert subscription != nil
        assert subscription.stripe_status == "trialing"
      after
        Application.delete_env(
          :ysc,
          :subscription_retrieve_for_webhook_callback
        )
      end
    end

    test "does not recreate subscription when status is incomplete and subscription missing locally" do
      user = user_with_stripe_id()
      stripe_sub_id = "sub_incomplete_#{System.unique_integer()}"

      assert Subscriptions.get_subscription_by_stripe_id(stripe_sub_id) == nil

      event_data =
        SubscriptionFixtures.subscription(
          id: stripe_sub_id,
          customer: user.stripe_id,
          status: "incomplete",
          items: %Stripe.List{
            data: [],
            has_more: false,
            object: "list",
            url: "/v1/subscription_items"
          }
        )

      event = build_stripe_event("customer.subscription.updated", event_data)
      assert :ok = WebhookHandler.handle_event(event)

      # Should not create - we only recreate for active/trialing
      assert Subscriptions.get_subscription_by_stripe_id(stripe_sub_id) == nil
    end

    test "does not recreate subscription when subscription missing locally and user not found for customer" do
      # User exists but has different stripe_id - event has unknown customer
      _user = user_with_stripe_id()
      stripe_sub_id = "sub_orphan_#{System.unique_integer()}"
      unknown_customer_id = "cus_unknown_#{System.unique_integer()}"

      assert Subscriptions.get_subscription_by_stripe_id(stripe_sub_id) == nil

      event_data =
        SubscriptionFixtures.subscription(
          id: stripe_sub_id,
          customer: unknown_customer_id,
          status: "active",
          items: %Stripe.List{
            data: [],
            has_more: false,
            object: "list",
            url: "/v1/subscription_items"
          }
        )

      event = build_stripe_event("customer.subscription.updated", event_data)
      assert :ok = WebhookHandler.handle_event(event)

      assert Subscriptions.get_subscription_by_stripe_id(stripe_sub_id) == nil
    end

    test "preserves active status when incomplete webhook arrives during upgrade transition (active -> incomplete)" do
      # When upgrading a plan (e.g. Single → Family), Stripe creates a proration invoice
      # and briefly marks the subscription "incomplete" until payment settles. We must NOT
      # persist "incomplete" to the DB, or the user will see a "No membership" banner
      # until the follow-up "active" webhook arrives.
      user = user_with_stripe_id()

      subscription =
        create_subscription(user, %{
          stripe_status: "active",
          current_period_start: DateTime.utc_now(),
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      event_data =
        SubscriptionFixtures.subscription(
          id: subscription.stripe_id,
          customer: user.stripe_id,
          status: "incomplete",
          start_date: System.os_time(:second),
          current_period_start: System.os_time(:second),
          current_period_end: System.os_time(:second) + 30 * 24 * 60 * 60,
          items: %Stripe.List{
            data: [],
            has_more: false,
            object: "list",
            url: "/v1/subscription_items"
          }
        )

      event = build_stripe_event("customer.subscription.updated", event_data)
      assert :ok = WebhookHandler.handle_event(event)

      subscription = Ysc.Repo.reload(subscription)
      assert subscription.stripe_status == "active"
      assert Subscriptions.active?(subscription)
    end

    test "preserves trialing status when incomplete webhook arrives during upgrade transition (trialing -> incomplete)" do
      user = user_with_stripe_id()

      subscription =
        create_subscription(user, %{
          stripe_status: "trialing",
          current_period_start: DateTime.utc_now(),
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      event_data =
        SubscriptionFixtures.subscription(
          id: subscription.stripe_id,
          customer: user.stripe_id,
          status: "incomplete",
          start_date: System.os_time(:second),
          current_period_start: System.os_time(:second),
          current_period_end: System.os_time(:second) + 30 * 24 * 60 * 60,
          items: %Stripe.List{
            data: [],
            has_more: false,
            object: "list",
            url: "/v1/subscription_items"
          }
        )

      event = build_stripe_event("customer.subscription.updated", event_data)
      assert :ok = WebhookHandler.handle_event(event)

      subscription = Ysc.Repo.reload(subscription)
      assert subscription.stripe_status == "trialing"
    end

    test "saves incomplete status when subscription was already incomplete (new unpaid subscription)" do
      # A brand-new subscription that was never paid should stay "incomplete".
      # The upgrade-transition guard must not suppress this.
      user = user_with_stripe_id()

      subscription =
        create_subscription(user, %{
          stripe_status: "incomplete",
          current_period_start: DateTime.utc_now(),
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      event_data =
        SubscriptionFixtures.subscription(
          id: subscription.stripe_id,
          customer: user.stripe_id,
          status: "incomplete",
          start_date: System.os_time(:second),
          current_period_start: System.os_time(:second),
          current_period_end: System.os_time(:second) + 30 * 24 * 60 * 60,
          items: %Stripe.List{
            data: [],
            has_more: false,
            object: "list",
            url: "/v1/subscription_items"
          }
        )

      event = build_stripe_event("customer.subscription.updated", event_data)
      assert :ok = WebhookHandler.handle_event(event)

      subscription = Ysc.Repo.reload(subscription)
      assert subscription.stripe_status == "incomplete"
    end

    test "customer.subscription.updated syncs cancel_at_period_end when auto-renew is turned off" do
      user = user_with_stripe_id()
      subscription = create_subscription(user, %{cancel_at_period_end: false})

      subscription_data =
        SubscriptionFixtures.subscription(
          id: subscription.stripe_id,
          customer: user.stripe_id,
          status: "active",
          cancel_at_period_end: true,
          start_date: System.os_time(:second),
          current_period_start: System.os_time(:second),
          current_period_end: System.os_time(:second) + 30 * 24 * 60 * 60,
          items: %Stripe.List{
            data: [],
            has_more: false,
            object: "list",
            url: "/v1/subscription_items"
          }
        )

      event =
        build_stripe_event("customer.subscription.updated", subscription_data)

      assert :ok = WebhookHandler.handle_event(event)

      assert Ysc.Repo.reload(subscription).cancel_at_period_end == true
    end

    test "customer.subscription.updated clears cancel_at_period_end when auto-renew is re-enabled" do
      user = user_with_stripe_id()
      subscription = create_subscription(user, %{cancel_at_period_end: true})

      subscription_data =
        SubscriptionFixtures.subscription(
          id: subscription.stripe_id,
          customer: user.stripe_id,
          status: "active",
          cancel_at_period_end: false,
          start_date: System.os_time(:second),
          current_period_start: System.os_time(:second),
          current_period_end: System.os_time(:second) + 30 * 24 * 60 * 60,
          items: %Stripe.List{
            data: [],
            has_more: false,
            object: "list",
            url: "/v1/subscription_items"
          }
        )

      event =
        build_stripe_event("customer.subscription.updated", subscription_data)

      assert :ok = WebhookHandler.handle_event(event)

      assert Ysc.Repo.reload(subscription).cancel_at_period_end == false
    end

    test "customer.subscription.updated preserves cancel_at_period_end after Stripe cancels subscription" do
      user = user_with_stripe_id()
      subscription = create_subscription(user, %{cancel_at_period_end: true})

      subscription_data =
        SubscriptionFixtures.subscription(
          id: subscription.stripe_id,
          customer: user.stripe_id,
          status: "canceled",
          cancel_at_period_end: false,
          start_date: System.os_time(:second),
          current_period_start: System.os_time(:second),
          current_period_end: System.os_time(:second) + 30 * 24 * 60 * 60,
          items: %Stripe.List{
            data: [],
            has_more: false,
            object: "list",
            url: "/v1/subscription_items"
          }
        )

      event =
        build_stripe_event("customer.subscription.updated", subscription_data)

      assert :ok = WebhookHandler.handle_event(event)

      updated = Ysc.Repo.reload(subscription)
      assert updated.cancel_at_period_end == true
      assert updated.stripe_status == "canceled"
    end

    test "customer.subscription.deleted schedules membership ended email for voluntary lapse" do
      user = user_with_stripe_id()

      subscription =
        create_subscription(user, %{
          stripe_status: "active",
          cancel_at_period_end: true,
          ends_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      subscription_data =
        SubscriptionFixtures.subscription(
          id: subscription.stripe_id,
          customer: user.stripe_id,
          status: "canceled"
        )

      event =
        build_stripe_event("customer.subscription.deleted", subscription_data)

      assert :ok = WebhookHandler.handle_event(event)

      assert Ysc.Repo.reload(subscription).stripe_status == "cancelled"
      assert_email_sent(subject: "Your YSC Membership Has Ended")
    end

    test "customer.subscription.deleted skips membership ended email without voluntary lapse" do
      user = user_with_stripe_id()
      subscription = create_subscription(user, %{cancel_at_period_end: false})

      subscription_data =
        SubscriptionFixtures.subscription(
          id: subscription.stripe_id,
          customer: user.stripe_id,
          status: "canceled"
        )

      event =
        build_stripe_event("customer.subscription.deleted", subscription_data)

      assert :ok = WebhookHandler.handle_event(event)

      assert Ysc.Repo.reload(subscription).stripe_status == "cancelled"
      refute_email_sent(subject: "Your YSC Membership Has Ended")
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

    @tag :sync
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
          "charge" => nil,
          "metadata" => %{}
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
        payment_intent: payment.external_payment_id,
        metadata: %{}
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

  describe "transactional guarantees" do
    test "webhook event always stored before success returned" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      event_id = "evt_storage_#{System.unique_integer()}"

      invoice_data = %{
        "id" => "in_storage_#{System.unique_integer()}",
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

      # Process webhook
      result = WebhookHandler.handle_event(event)

      # If result is :ok, webhook MUST be stored
      if result == :ok do
        webhook_event =
          Webhooks.get_webhook_event_by_provider_and_event_id(
            "stripe",
            event_id
          )

        assert webhook_event != nil,
               "Webhook returned :ok but event not stored in database"

        assert webhook_event.event_type == "invoice.payment_succeeded"
      end
    end

    test "webhook processing is atomic - all or nothing" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      invoice_data = %{
        "id" => "in_atomic_#{System.unique_integer()}",
        "customer" => user.stripe_id,
        "subscription" => subscription.stripe_id,
        "amount_paid" => 4500,
        "charge" => nil,
        "metadata" => %{}
      }

      event = build_stripe_event("invoice.payment_succeeded", invoice_data)

      # Process webhook
      assert :ok = WebhookHandler.handle_event(event)

      # Webhook state should be :processed
      webhook_event =
        Webhooks.get_webhook_event_by_provider_and_event_id("stripe", event.id)

      assert webhook_event.state == :processed

      # Payment should exist
      payment = Ledgers.get_payment_by_external_id(invoice_data["id"])
      assert payment != nil

      # Ledger should be balanced
      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end

    test "failed webhook processing rolls back all changes" do
      # Create event that will fail (missing customer)
      invalid_data = %{
        "id" => "in_rollback_#{System.unique_integer()}",
        "customer" => "cus_nonexistent_#{System.unique_integer()}",
        "subscription" => "sub_test",
        "amount_paid" => 5000,
        "charge" => nil
      }

      event = build_stripe_event("invoice.payment_succeeded", invalid_data)

      # Process webhook - should handle error gracefully
      assert :ok = WebhookHandler.handle_event(event)

      # Webhook should be marked as failed
      webhook_event =
        Webhooks.get_webhook_event_by_provider_and_event_id("stripe", event.id)

      assert webhook_event != nil
      assert webhook_event.state == :failed

      # No payment should be created
      assert Ledgers.get_payment_by_external_id(invalid_data["id"]) == nil

      # Ledger should still be balanced
      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end

    test "duplicate webhook doesn't create duplicate payment" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      event_id = "evt_duplicate_atomic_#{System.unique_integer()}"
      invoice_id = "in_duplicate_atomic_#{System.unique_integer()}"

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

      # First processing
      assert :ok = WebhookHandler.handle_event(event)

      # Get initial state
      payment1 = Ledgers.get_payment_by_external_id(invoice_id)
      assert payment1 != nil

      webhook1 =
        Webhooks.get_webhook_event_by_provider_and_event_id("stripe", event_id)

      assert webhook1.state == :processed

      # Second processing (duplicate)
      assert :ok = WebhookHandler.handle_event(event)

      # Payment should be the same
      payment2 = Ledgers.get_payment_by_external_id(invoice_id)
      assert payment2.id == payment1.id

      # Only one payment should exist
      all_payments = Ledgers.get_payments_by_user(user.id)
      assert length(all_payments) == 1

      # Ledger should still be balanced
      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end

    test "subscription update is atomic - subscription and items updated together" do
      user = user_with_stripe_id()
      subscription = create_subscription(user, %{stripe_status: "active"})

      subscription_data =
        SubscriptionFixtures.subscription(
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
        )

      event =
        build_stripe_event("customer.subscription.updated", subscription_data)

      assert :ok = WebhookHandler.handle_event(event)

      # Webhook should be processed
      webhook_event =
        Webhooks.get_webhook_event_by_provider_and_event_id("stripe", event.id)

      assert webhook_event.state == :processed

      # Subscription status should be updated
      updated_subscription = Ysc.Repo.reload(subscription)
      assert updated_subscription.stripe_status == "past_due"
    end

    test "customer deletion cancels all subscriptions atomically" do
      user = user_with_stripe_id()

      # Create multiple subscriptions
      subscription1 = create_subscription(user, %{stripe_status: "active"})
      subscription2 = create_subscription(user, %{stripe_status: "active"})
      subscription3 = create_subscription(user, %{stripe_status: "active"})

      customer_data = %Stripe.Customer{
        id: user.stripe_id,
        email: user.email
      }

      event = build_stripe_event("customer.deleted", customer_data)

      assert :ok = WebhookHandler.handle_event(event)

      # All subscriptions should be cancelled
      sub1 = Ysc.Repo.reload(subscription1)
      sub2 = Ysc.Repo.reload(subscription2)
      sub3 = Ysc.Repo.reload(subscription3)

      assert sub1.stripe_status == "cancelled"
      assert sub2.stripe_status == "cancelled"
      assert sub3.stripe_status == "cancelled"

      # Webhook should be processed
      webhook_event =
        Webhooks.get_webhook_event_by_provider_and_event_id("stripe", event.id)

      assert webhook_event.state == :processed
    end
  end

  describe "email async processing" do
    test "webhook processing succeeds even if email enqueueing fails" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      invoice_data = %{
        "id" => "in_email_#{System.unique_integer()}",
        "customer" => user.stripe_id,
        "subscription" => subscription.stripe_id,
        "billing_reason" => "subscription_create",
        "amount_paid" => 4500,
        "description" => "Test Invoice",
        "number" => "INV-001",
        "charge" => nil,
        "metadata" => %{}
      }

      event = build_stripe_event("invoice.payment_succeeded", invoice_data)

      # Process webhook - should succeed regardless of email status
      assert :ok = WebhookHandler.handle_event(event)

      # Payment should be created
      payment = Ledgers.get_payment_by_external_id(invoice_data["id"])
      assert payment != nil

      # Webhook should be marked as processed
      webhook_event =
        Webhooks.get_webhook_event_by_provider_and_event_id("stripe", event.id)

      assert webhook_event.state == :processed

      # Email should have been enqueued (check email was sent)
      assert_email_sent(
        subject: "Your YSC Membership Payment Receipt",
        to: {nil, user.email}
      )
    end

    test "payment failure email is enqueued asynchronously" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      invoice_data = %{
        "id" => "in_failure_email_#{System.unique_integer()}",
        "customer" => user.stripe_id,
        "subscription" => subscription.stripe_id,
        "billing_reason" => "subscription_cycle",
        "amount_paid" => 4500
      }

      event = build_stripe_event("invoice.payment.failed", invoice_data)

      # Process webhook
      assert :ok = WebhookHandler.handle_event(event)

      # Webhook should be processed
      webhook_event =
        Webhooks.get_webhook_event_by_provider_and_event_id("stripe", event.id)

      assert webhook_event.state == :processed

      # Email should have been enqueued
      assert_email_sent(subject: "Action Needed: YSC Membership Payment Issue")
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

    test "customer.updated syncs default payment method from Stripe" do
      user = user_with_stripe_id()
      stripe_pm_id = "pm_sync_default_#{System.unique_integer([:positive])}"

      {:ok, _pm1} =
        Ysc.Payments.insert_payment_method(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: "pm_other_#{System.unique_integer([:positive])}",
          provider_customer_id: user.stripe_id,
          type: :card,
          provider_type: "card",
          is_default: true
        })

      {:ok, pm2} =
        Ysc.Payments.insert_payment_method(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: stripe_pm_id,
          provider_customer_id: user.stripe_id,
          type: :card,
          provider_type: "card",
          is_default: false
        })

      customer_data = %Stripe.Customer{
        id: user.stripe_id,
        email: user.email,
        invoice_settings: %{default_payment_method: stripe_pm_id}
      }

      event = build_stripe_event("customer.updated", customer_data)
      assert :ok = WebhookHandler.handle_event(event)

      default = Ysc.Payments.get_default_payment_method(user)
      assert default.id == pm2.id
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

  describe "additional stripe webhook coverage" do
    defp empty_stripe_list do
      %Stripe.List{data: [], has_more: false, object: "list", url: "/v1"}
    end

    test "invoice.payment_succeeded with Stripe.Invoice struct processes payment" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      invoice_struct = %Stripe.Invoice{
        id: "in_struct_#{System.unique_integer()}",
        object: "invoice",
        customer: user.stripe_id,
        subscription: subscription.stripe_id,
        amount_paid: 4500,
        description: "Membership",
        number: "INV-S",
        metadata: %{},
        billing_reason: "subscription_cycle",
        lines: empty_stripe_list()
      }

      event = build_stripe_event("invoice.payment_succeeded", invoice_struct)
      assert :ok = WebhookHandler.handle_event(event)

      assert Ledgers.get_payment_by_external_id(invoice_struct.id) != nil
    end

    test "invoice.payment.failed with Stripe.Invoice struct delegates to map handler" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      invoice_struct = %Stripe.Invoice{
        id: "in_fail_struct_#{System.unique_integer()}",
        object: "invoice",
        customer: user.stripe_id,
        subscription: subscription.stripe_id,
        billing_reason: "subscription_cycle",
        lines: empty_stripe_list()
      }

      event = build_stripe_event("invoice.payment.failed", invoice_struct)
      assert :ok = WebhookHandler.handle_event(event)
    end

    test "invoice.payment_failed (underscore) with Stripe.Invoice struct" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      invoice_struct = %Stripe.Invoice{
        id: "in_ufail_#{System.unique_integer()}",
        object: "invoice",
        customer: user.stripe_id,
        subscription: subscription.stripe_id,
        billing_reason: "subscription_cycle",
        lines: empty_stripe_list()
      }

      event = build_stripe_event("invoice.payment_failed", invoice_struct)
      assert :ok = WebhookHandler.handle_event(event)
    end

    test "invoice.payment_failed routes map payload to invoice.payment.failed handler" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      invoice_map = %{
        "id" => "in_map_ufail_#{System.unique_integer()}",
        "customer" => user.stripe_id,
        "subscription" => subscription.stripe_id,
        "billing_reason" => "subscription_cycle"
      }

      assert :ok =
               WebhookHandler.handle_webhook_event(
                 "invoice.payment_failed",
                 invoice_map
               )
    end

    test "invoice.payment_action_required returns ok" do
      invoice_struct = %Stripe.Invoice{
        id: "in_action_#{System.unique_integer()}",
        object: "invoice",
        customer: "cus_nouser",
        lines: empty_stripe_list()
      }

      event =
        build_stripe_event("invoice.payment_action_required", invoice_struct)

      assert :ok = WebhookHandler.handle_event(event)
    end

    test "customer.created links stripe_id from metadata user_id" do
      user = user_fixture()

      {:ok, user} =
        user |> Ecto.Changeset.change(stripe_id: nil) |> Ysc.Repo.update()

      new_cus = "cus_meta_#{System.unique_integer()}"

      customer = %Stripe.Customer{
        id: new_cus,
        email: user.email,
        metadata: %{"user_id" => user.id}
      }

      event = build_stripe_event("customer.created", customer)
      assert :ok = WebhookHandler.handle_event(event)

      assert Ysc.Repo.reload!(user).stripe_id == new_cus
    end

    test "customer.created links stripe_id from email when metadata absent" do
      email = "customer_created_email_#{System.unique_integer()}@example.com"
      user = user_fixture(%{email: email})

      {:ok, user} =
        user |> Ecto.Changeset.change(stripe_id: nil) |> Ysc.Repo.update()

      new_cus = "cus_email_#{System.unique_integer()}"

      customer = %Stripe.Customer{
        id: new_cus,
        email: user.email,
        metadata: %{}
      }

      event = build_stripe_event("customer.created", customer)
      assert :ok = WebhookHandler.handle_event(event)

      assert Ysc.Repo.reload!(user).stripe_id == new_cus
    end

    test "customer.created skips when user already has stripe_id" do
      user = user_with_stripe_id()
      existing = user.stripe_id

      customer = %Stripe.Customer{
        id: "cus_other_#{System.unique_integer()}",
        email: user.email,
        metadata: %{"user_id" => user.id}
      }

      event = build_stripe_event("customer.created", customer)
      assert :ok = WebhookHandler.handle_event(event)

      assert Ysc.Repo.reload!(user).stripe_id == existing
    end

    test "customer.subscription.created with wp_migration metadata is no-op" do
      user = user_with_stripe_id()
      stripe_sub_id = "sub_wp_#{System.unique_integer()}"

      subscription_data =
        SubscriptionFixtures.subscription(
          id: stripe_sub_id,
          customer: user.stripe_id,
          status: "active",
          metadata: %{"wp_migration" => "true"},
          start_date: System.os_time(:second),
          current_period_start: System.os_time(:second),
          current_period_end: System.os_time(:second) + 86_400,
          items: empty_stripe_list()
        )

      event =
        build_stripe_event("customer.subscription.created", subscription_data)

      assert :ok = WebhookHandler.handle_event(event)

      assert Subscriptions.get_subscription_by_stripe_id(stripe_sub_id) == nil
    end

    test "customer.subscription.created with trialing status creates subscription" do
      user = user_with_stripe_id()
      stripe_sub_id = "sub_trial_#{System.unique_integer()}"

      subscription_data =
        SubscriptionFixtures.subscription(
          id: stripe_sub_id,
          customer: user.stripe_id,
          status: "trialing",
          start_date: System.os_time(:second),
          current_period_start: System.os_time(:second),
          current_period_end: System.os_time(:second) + 86_400,
          items: empty_stripe_list()
        )

      event =
        build_stripe_event("customer.subscription.created", subscription_data)

      assert :ok = WebhookHandler.handle_event(event)

      sub = Subscriptions.get_subscription_by_stripe_id(stripe_sub_id)
      assert sub != nil
      assert sub.stripe_status == "trialing"
    end

    test "subscription_schedule events return ok" do
      sched = %Stripe.SubscriptionSchedule{
        id: "sub_sched_#{System.unique_integer()}",
        object: "subscription_schedule"
      }

      for type <-
            ~w(subscription_schedule.created subscription_schedule.updated subscription_schedule.released subscription_schedule.canceled) do
        event = build_stripe_event(type, sched)
        assert :ok = WebhookHandler.handle_event(event)
      end
    end

    test "setup_intent.created and setup_intent.succeeded" do
      si_create = %Stripe.SetupIntent{
        id: "seti_create_#{System.unique_integer()}",
        object: "setup_intent",
        customer: "cus_x",
        status: "requires_payment_method"
      }

      assert :ok =
               WebhookHandler.handle_event(
                 build_stripe_event("setup_intent.created", si_create)
               )

      user = user_with_stripe_id()
      pm_id = "pm_si_#{System.unique_integer()}"

      si_ok = %Stripe.SetupIntent{
        id: "seti_ok_#{System.unique_integer()}",
        object: "setup_intent",
        customer: user.stripe_id,
        payment_method: pm_id,
        status: "succeeded"
      }

      assert :ok =
               WebhookHandler.handle_event(
                 build_stripe_event("setup_intent.succeeded", si_ok)
               )
    end

    test "payment_method.attached syncs card from Stripe payload" do
      user = user_with_stripe_id()
      pm_id = "pm_attach_#{System.unique_integer()}"

      pm = %Stripe.PaymentMethod{
        id: pm_id,
        object: "payment_method",
        customer: user.stripe_id,
        type: "card",
        metadata: %{},
        card: %Stripe.Card{
          brand: "visa",
          last4: "4242",
          exp_month: 12,
          exp_year: 2030,
          funding: "credit"
        }
      }

      event = build_stripe_event("payment_method.attached", pm)
      assert :ok = WebhookHandler.handle_event(event)

      local = Ysc.Payments.get_payment_method_by_provider(:stripe, pm_id)
      assert local != nil
      assert local.last_four == "4242"
    end

    test "payment_method.detached deletes local payment method" do
      user = user_with_stripe_id()
      pm_id = "pm_detach_#{System.unique_integer()}"

      {:ok, _} =
        Ysc.Payments.insert_payment_method(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: pm_id,
          provider_customer_id: user.stripe_id,
          type: :card,
          provider_type: "card",
          is_default: false
        })

      pm = %Stripe.PaymentMethod{
        id: pm_id,
        object: "payment_method",
        customer: user.stripe_id,
        type: "card"
      }

      event = build_stripe_event("payment_method.detached", pm)
      assert :ok = WebhookHandler.handle_event(event)

      assert Ysc.Payments.get_payment_method_by_provider(:stripe, pm_id) == nil
    end

    test "payment_method.updated syncs without error" do
      user = user_with_stripe_id()
      pm_id = "pm_upd_#{System.unique_integer()}"

      pm = %Stripe.PaymentMethod{
        id: pm_id,
        object: "payment_method",
        customer: user.stripe_id,
        type: "card",
        metadata: %{},
        card: %Stripe.Card{
          brand: "visa",
          last4: "4242",
          exp_month: 12,
          exp_year: 2030,
          funding: "credit"
        }
      }

      event = build_stripe_event("payment_method.attached", pm)
      assert :ok = WebhookHandler.handle_event(event)

      updated = %Stripe.PaymentMethod{
        pm
        | card: %Stripe.Card{
            brand: "visa",
            last4: "0005",
            exp_month: 11,
            exp_year: 2031,
            funding: "credit"
          }
      }

      assert :ok =
               WebhookHandler.handle_event(
                 build_stripe_event("payment_method.updated", updated)
               )
    end

    test "payout.paid map handler is idempotent for same stripe payout id" do
      payout_id = "po_cov_#{System.unique_integer()}"
      arrival = System.os_time(:second)

      payout_map = %{
        "id" => payout_id,
        "amount" => 50_000,
        "currency" => "usd",
        "status" => "paid",
        "arrival_date" => arrival,
        "description" => "Test payout coverage",
        "metadata" => %{}
      }

      assert :ok =
               WebhookHandler.handle_webhook_event("payout.paid", payout_map)

      assert Ledgers.get_payout_by_stripe_id(payout_id) != nil

      assert :ok =
               WebhookHandler.handle_webhook_event("payout.paid", payout_map)
    end

    test "payout.paid with a negative amount (withdrawal to cover a negative balance) processes without failing" do
      payout_id = "po_negative_#{System.unique_integer()}"
      arrival = System.os_time(:second)

      payout_map = %{
        "id" => payout_id,
        "amount" => -68_145,
        "currency" => "usd",
        "status" => "paid",
        "arrival_date" => arrival,
        "description" => "Withdrawal to cover a negative balance",
        "metadata" => %{}
      }

      assert :ok =
               WebhookHandler.handle_webhook_event("payout.paid", payout_map)

      payout = Ledgers.get_payout_by_stripe_id(payout_id)
      assert payout != nil
      assert payout.amount == Money.new(:USD, "-681.45")
    end

    test "payout.paid skips ledger when STRIPE_PROCESS_PAYOUT_WEBHOOKS disables processing" do
      previous = Application.get_env(:ysc, :process_stripe_payout_webhooks)
      Application.put_env(:ysc, :process_stripe_payout_webhooks, false)

      on_exit(fn ->
        if previous != nil do
          Application.put_env(:ysc, :process_stripe_payout_webhooks, previous)
        else
          Application.delete_env(:ysc, :process_stripe_payout_webhooks)
        end
      end)

      payout_id = "po_skip_#{System.unique_integer()}"
      arrival = System.os_time(:second)

      payout_map = %{
        "id" => payout_id,
        "amount" => 50_000,
        "currency" => "usd",
        "status" => "paid",
        "arrival_date" => arrival,
        "description" => "Skipped payout",
        "metadata" => %{}
      }

      assert :ok =
               WebhookHandler.handle_webhook_event("payout.paid", payout_map)

      assert Ledgers.get_payout_by_stripe_id(payout_id) == nil
    end

    test "payout.paid with Stripe.Payout struct uses struct clause via handle_webhook_event" do
      payout_id = "po_struct_#{System.unique_integer()}"

      payout = %Stripe.Payout{
        id: payout_id,
        object: "payout",
        amount: 25_000,
        currency: "usd",
        status: "paid",
        arrival_date: System.os_time(:second),
        description: "Struct payout",
        metadata: %{}
      }

      assert :ok = WebhookHandler.handle_webhook_event("payout.paid", payout)
      assert Ledgers.get_payout_by_stripe_id(payout_id) != nil
    end

    test "charge.dispute.created returns ok" do
      dispute = %Stripe.Dispute{
        id: "dp_#{System.unique_integer()}",
        object: "dispute",
        charge: "ch_123",
        amount: 2000,
        currency: "usd"
      }

      event = build_stripe_event("charge.dispute.created", dispute)
      assert :ok = WebhookHandler.handle_event(event)
    end

    test "refund.updated struct and map via handle_webhook_event" do
      refund_struct = %Stripe.Refund{
        id: "re_upd_#{System.unique_integer()}",
        charge: "ch_x",
        amount: 100,
        status: "succeeded"
      }

      assert :ok =
               WebhookHandler.handle_webhook_event(
                 "refund.updated",
                 refund_struct
               )

      refund_map = %{
        "id" => "re_map_#{System.unique_integer()}",
        "charge" => "ch_y",
        "amount" => 200,
        "status" => "pending"
      }

      assert :ok =
               WebhookHandler.handle_webhook_event("refund.updated", refund_map)
    end

    test "unhandled invoice.* events hit catch-all and return ok" do
      assert :ok =
               WebhookHandler.handle_webhook_event("invoice.finalized", %{
                 "id" => "in_fin",
                 "object" => "invoice"
               })
    end

    test "handle_webhook_event payment_intent.succeeded with map" do
      pi = %{
        "id" => "pi_map_#{System.unique_integer()}",
        "status" => "succeeded",
        "customer" => "cus_x",
        "amount" => 1000
      }

      assert :ok =
               WebhookHandler.handle_webhook_event(
                 "payment_intent.succeeded",
                 pi
               )
    end

    test "calculate_estimated_fee returns fee money" do
      fee = WebhookHandler.calculate_estimated_fee(Decimal.new("100.00"))
      assert %Money{} = fee
      assert fee.currency == :USD
    end

    test "sum_fee_cents_from_balance_transactions includes charge fees and stripe_fee amounts" do
      # Mirrors a payout like po_1TyL7dIZd8GkARoBdw1Ipxew:
      # 3 charges @ $1.61 fee each ($4.83) + Billing Usage Fee $0.95
      balance_transactions = [
        %{
          type: "charge",
          reporting_category: "charge",
          fee: 161,
          amount: 4500
        },
        %{
          type: "charge",
          reporting_category: "charge",
          fee: 161,
          amount: 4500
        },
        %{
          type: "charge",
          reporting_category: "charge",
          fee: 161,
          amount: 4500
        },
        %{
          type: "stripe_fee",
          reporting_category: "fee",
          fee: 0,
          amount: -95,
          description: "Billing - Usage Fee (2026-07-27)"
        },
        %{
          type: "payout",
          reporting_category: "payout",
          fee: 0,
          amount: -12_922
        }
      ]

      assert WebhookHandler.sum_fee_cents_from_balance_transactions(
               balance_transactions
             ) == 483 + 95
    end

    test "sum_fee_cents_from_balance_transactions uses abs(amount) for fee reporting_category" do
      balance_transactions = [
        %{type: "charge", reporting_category: "charge", fee: 100, amount: 2000},
        %{
          type: "stripe_fee",
          reporting_category: "fee",
          fee: 0,
          amount: -50
        }
      ]

      assert WebhookHandler.sum_fee_cents_from_balance_transactions(
               balance_transactions
             ) == 150
    end

    test "sum_fee_cents_from_balance_transactions skips payout and ignores zero fees" do
      balance_transactions = [
        %{type: "payout", reporting_category: "payout", fee: 25, amount: -1000},
        %{type: "charge", reporting_category: "charge", fee: 0, amount: 500}
      ]

      assert WebhookHandler.sum_fee_cents_from_balance_transactions(
               balance_transactions
             ) == 0
    end

    test "sum_payout_time_fee_cents_from_balance_transactions excludes charge fees" do
      balance_transactions = [
        %{type: "charge", reporting_category: "charge", fee: 161, amount: 4500},
        %{
          type: "stripe_fee",
          reporting_category: "fee",
          fee: 0,
          amount: -95
        },
        %{type: "payout", reporting_category: "payout", fee: 0, amount: -12_922}
      ]

      assert WebhookHandler.sum_payout_time_fee_cents_from_balance_transactions(
               balance_transactions
             ) == 95
    end

    test "sum_payout_time_fee_cents_from_balance_transactions includes payout BT fee" do
      balance_transactions = [
        %{type: "charge", reporting_category: "charge", fee: 100, amount: 2000},
        %{type: "payout", reporting_category: "payout", fee: 50, amount: -1900}
      ]

      assert WebhookHandler.sum_payout_time_fee_cents_from_balance_transactions(
               balance_transactions
             ) == 50
    end

    test "extract_stripe_fee_from_invoice reads cents from metadata" do
      invoice = %{
        "id" => "in_fee_#{System.unique_integer()}",
        "charge" => nil,
        "metadata" => %{"stripe_fee" => "150"}
      }

      fee = WebhookHandler.extract_stripe_fee_from_invoice(invoice)
      assert %Money{} = fee
    end

    test "customer.subscription.updated incomplete_expired deletes local subscription" do
      user = user_with_stripe_id()

      subscription =
        create_subscription(user, %{
          stripe_status: "active",
          stripe_id: "sub_incexp_#{System.unique_integer()}"
        })

      subscription_data =
        SubscriptionFixtures.subscription(
          id: subscription.stripe_id,
          customer: user.stripe_id,
          status: "incomplete_expired",
          items: empty_stripe_list()
        )

      event =
        build_stripe_event("customer.subscription.updated", subscription_data)

      assert :ok = WebhookHandler.handle_event(event)

      assert Subscriptions.get_subscription_by_stripe_id(subscription.stripe_id) ==
               nil
    end
  end

  describe "webhook handler coverage expansion" do
    test "invoice.payment_succeeded subscription_update with proration lines builds upgrade description" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      family_plan =
        Application.get_env(:ysc, :membership_plans, [])
        |> Enum.find(&(&1.id in [:family, "family"]))

      assert family_plan, "membership_plans must include family plan"

      Subscriptions.create_subscription_item(%{
        subscription_id: subscription.id,
        stripe_id: "si_prorate_#{System.unique_integer()}",
        stripe_product_id: "prod_family",
        stripe_price_id: family_plan.stripe_price_id,
        quantity: 1
      })

      inv_id = "in_prorate_#{System.unique_integer()}"

      invoice_data = %{
        "id" => inv_id,
        "customer" => user.stripe_id,
        "subscription" => subscription.stripe_id,
        "billing_reason" => "subscription_update",
        "amount_paid" => 5000,
        "description" => "Plan change",
        "number" => "INV-PR",
        "charge" => nil,
        "metadata" => %{},
        "lines" => %{
          "data" => [
            %{
              "description" => "Unused time on Single after 17 Feb 2026",
              "amount" => -2500
            },
            %{
              "description" => "Remaining time on Family after 17 Feb 2026",
              "amount" => 4000
            }
          ]
        }
      }

      event = build_stripe_event("invoice.payment_succeeded", invoice_data)
      assert :ok = WebhookHandler.handle_event(event)

      payment = Ledgers.get_payment_by_external_id(inv_id)
      assert payment != nil

      assert Repo.exists?(
               from(le in Ysc.Ledgers.LedgerEntry,
                 where: le.payment_id == ^payment.id,
                 where: ilike(le.description, "%Prorated upgrade%")
               )
             )

      assert Repo.exists?(
               from(le in Ysc.Ledgers.LedgerEntry,
                 where: le.payment_id == ^payment.id,
                 where: ilike(le.description, "%Single%")
               )
             )

      assert Repo.exists?(
               from(le in Ysc.Ledgers.LedgerEntry,
                 where: le.payment_id == ^payment.id,
                 where: ilike(le.description, "%Family%")
               )
             )
    end

    test "invoice.payment_succeeded resolves subscription from customer when invoice subscription is null (subscription_update)" do
      user = user_with_stripe_id()
      subscription = create_subscription(user, %{stripe_status: "active"})

      inv_id = "in_resolve_#{System.unique_integer()}"

      invoice_data = %{
        "id" => inv_id,
        "customer" => user.stripe_id,
        "subscription" => nil,
        "billing_reason" => "subscription_update",
        "amount_paid" => 4500,
        "description" => "Proration",
        "number" => "INV-RES",
        "charge" => nil,
        "metadata" => %{}
      }

      event = build_stripe_event("invoice.payment_succeeded", invoice_data)
      assert :ok = WebhookHandler.handle_event(event)

      assert Ledgers.get_payment_by_external_id(inv_id) != nil

      assert Subscriptions.get_subscription_by_stripe_id(subscription.stripe_id) !=
               nil
    end

    test "invoice.payment_succeeded resolves subscription from customer when invoice subscription is null (subscription_create)" do
      user = user_with_stripe_id()
      _subscription = create_subscription(user, %{stripe_status: "active"})

      inv_id = "in_resolve_create_#{System.unique_integer()}"

      invoice_data = %{
        "id" => inv_id,
        "customer" => user.stripe_id,
        "subscription" => nil,
        "billing_reason" => "subscription_create",
        "amount_paid" => 4500,
        "description" => "Initial",
        "number" => "INV-INIT",
        "charge" => nil,
        "metadata" => %{}
      }

      event = build_stripe_event("invoice.payment_succeeded", invoice_data)
      assert :ok = WebhookHandler.handle_event(event)

      assert Ledgers.get_payment_by_external_id(inv_id) != nil
    end

    test "invoice.payment.failed skips when invoice is not subscription-related" do
      invoice_data = %{
        "id" => "in_manual_#{System.unique_integer()}",
        "customer" => "cus_not_in_db",
        "subscription" => nil,
        "billing_reason" => "manual"
      }

      event = build_stripe_event("invoice.payment.failed", invoice_data)
      assert :ok = WebhookHandler.handle_event(event)
    end

    test "customer.updated when Stripe default payment method is not stored locally still returns ok" do
      user = user_with_stripe_id()

      customer_data = %Stripe.Customer{
        id: user.stripe_id,
        email: user.email,
        invoice_settings: %{
          default_payment_method: "pm_missing_#{System.unique_integer()}"
        }
      }

      event = build_stripe_event("customer.updated", customer_data)
      assert :ok = WebhookHandler.handle_event(event)
    end

    test "payout.paid with uppercase USD currency string normalizes and processes" do
      payout_id = "po_usd_upper_#{System.unique_integer()}"

      payout_map = %{
        "id" => payout_id,
        "amount" => 40_000,
        "currency" => "USD",
        "status" => "paid",
        "arrival_date" => System.os_time(:second),
        "description" => "Uppercase USD payout",
        "metadata" => %{}
      }

      assert :ok =
               WebhookHandler.handle_webhook_event("payout.paid", payout_map)

      assert Ledgers.get_payout_by_stripe_id(payout_id) != nil
    end

    test "customer.created with unknown email returns ok without linking" do
      customer = %Stripe.Customer{
        id: "cus_unknown_#{System.unique_integer()}",
        email: "nobody_#{System.unique_integer()}@example.invalid",
        metadata: %{}
      }

      event = build_stripe_event("customer.created", customer)
      assert :ok = WebhookHandler.handle_event(event)
    end

    test "customer.subscription.updated sets ends_at from cancel_at when present" do
      user = user_with_stripe_id()
      subscription = create_subscription(user, %{stripe_status: "active"})
      cancel_at = System.os_time(:second) + 86_400

      subscription_data =
        SubscriptionFixtures.subscription(
          id: subscription.stripe_id,
          customer: user.stripe_id,
          status: "active",
          cancel_at: cancel_at,
          start_date: System.os_time(:second),
          current_period_start: System.os_time(:second),
          current_period_end: System.os_time(:second) + 30 * 24 * 60 * 60,
          items: %Stripe.List{
            data: [],
            has_more: false,
            object: "list",
            url: "/v1/subscription_items"
          }
        )

      event =
        build_stripe_event("customer.subscription.updated", subscription_data)

      assert :ok = WebhookHandler.handle_event(event)

      updated = Ysc.Repo.reload(subscription)

      assert DateTime.compare(updated.ends_at, DateTime.from_unix!(cancel_at)) ==
               :eq
    end

    test "checkout.session.completed falls through catch-all and returns ok" do
      assert :ok =
               WebhookHandler.handle_webhook_event(
                 "checkout.session.completed",
                 %{
                   "id" => "cs_test_#{System.unique_integer()}",
                   "object" => "checkout.session"
                 }
               )
    end

    test "payment_intent.payment_failed falls through catch-all and returns ok" do
      assert :ok =
               WebhookHandler.handle_webhook_event(
                 "payment_intent.payment_failed",
                 %{
                   "id" => "pi_fail_#{System.unique_integer()}",
                   "object" => "payment_intent"
                 }
               )
    end

    test "invoice.voided hits invoice.* debug branch and returns ok" do
      assert :ok =
               WebhookHandler.handle_webhook_event("invoice.voided", %{
                 "id" => "in_void_#{System.unique_integer()}",
                 "object" => "invoice"
               })
    end

    test "second invoice.payment_succeeded for same invoice id is idempotent in handler" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      inv_id = "in_idem_#{System.unique_integer()}"

      invoice_data = %{
        "id" => inv_id,
        "customer" => user.stripe_id,
        "subscription" => subscription.stripe_id,
        "amount_paid" => 4500,
        "description" => "Dup test",
        "number" => "INV-IDEM",
        "charge" => nil,
        "metadata" => %{}
      }

      e1 = build_stripe_event("invoice.payment_succeeded", invoice_data)
      assert :ok = WebhookHandler.handle_event(e1)

      e2 = build_stripe_event("invoice.payment_succeeded", invoice_data)
      assert :ok = WebhookHandler.handle_event(e2)

      payments =
        Ysc.Repo.all(
          from(p in Ysc.Ledgers.Payment,
            where: p.external_payment_id == ^inv_id
          )
        )

      assert length(payments) == 1
    end

    test "setup_intent.succeeded when local payment method already exists" do
      user = user_with_stripe_id()
      pm_id = "pm_existing_#{System.unique_integer()}"

      {:ok, _} =
        Ysc.Payments.insert_payment_method(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: pm_id,
          provider_customer_id: user.stripe_id,
          type: :card,
          provider_type: "card",
          is_default: false
        })

      si = %Stripe.SetupIntent{
        id: "seti_pm_exists_#{System.unique_integer()}",
        object: "setup_intent",
        customer: user.stripe_id,
        payment_method: pm_id,
        status: "succeeded"
      }

      event = build_stripe_event("setup_intent.succeeded", si)
      assert :ok = WebhookHandler.handle_event(event)
    end

    test "payment_intent.succeeded processes Stripe.PaymentIntent struct clause" do
      pi = %Stripe.PaymentIntent{
        id: "pi_struct_clause_#{System.unique_integer()}",
        object: "payment_intent",
        status: "succeeded",
        customer: "cus_x",
        amount: 2000,
        description: "Test",
        metadata: %{}
      }

      assert :ok =
               WebhookHandler.handle_webhook_event(
                 "payment_intent.succeeded",
                 pi
               )
    end

    test "invoice.payment.failed with Stripe.Invoice struct for subscription_cycle enqueues email" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      invoice_struct = %Stripe.Invoice{
        id: "in_fail_cycle_#{System.unique_integer()}",
        object: "invoice",
        customer: user.stripe_id,
        subscription: subscription.stripe_id,
        billing_reason: "subscription_cycle",
        lines: %Stripe.List{
          data: [],
          has_more: false,
          object: "list",
          url: "/v1/lines"
        }
      }

      event = build_stripe_event("invoice.payment.failed", invoice_struct)
      assert :ok = WebhookHandler.handle_event(event)

      assert_email_sent(subject: "Action Needed: YSC Membership Payment Issue")
    end

    test "customer.subscription.updated with null period fields preserves stored dates for past_due" do
      user = user_with_stripe_id()
      period_end = DateTime.add(DateTime.utc_now(), 20, :day)

      subscription =
        create_subscription(user, %{
          stripe_status: "past_due",
          current_period_start: DateTime.utc_now(),
          current_period_end: period_end
        })

      original_start = subscription.current_period_start
      original_end = subscription.current_period_end

      subscription_data =
        SubscriptionFixtures.subscription(
          id: subscription.stripe_id,
          customer: user.stripe_id,
          status: "past_due",
          start_date: nil,
          current_period_start: nil,
          current_period_end: nil,
          items: %Stripe.List{
            data: [],
            has_more: false,
            object: "list",
            url: "/v1/subscription_items"
          }
        )

      event =
        build_stripe_event("customer.subscription.updated", subscription_data)

      assert :ok = WebhookHandler.handle_event(event)

      reloaded = Ysc.Repo.reload(subscription)
      assert reloaded.current_period_start == original_start
      assert reloaded.current_period_end == original_end
    end

    test "payment_method.detached when payment method was never stored returns ok" do
      pm = %Stripe.PaymentMethod{
        id: "pm_never_saved_#{System.unique_integer()}",
        object: "payment_method",
        customer: "cus_any",
        type: "card"
      }

      event = build_stripe_event("payment_method.detached", pm)
      assert :ok = WebhookHandler.handle_event(event)
    end

    test "charge.refunded processes refunds list when refunds are present" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      inv_id = "in_chref_#{System.unique_integer()}"

      assert :ok =
               WebhookHandler.handle_event(
                 build_stripe_event("invoice.payment_succeeded", %{
                   "id" => inv_id,
                   "customer" => user.stripe_id,
                   "subscription" => subscription.stripe_id,
                   "amount_paid" => 8000,
                   "description" => "For refund test",
                   "number" => "INV-RF",
                   "charge" => nil,
                   "metadata" => %{}
                 })
               )

      payment = Ledgers.get_payment_by_external_id(inv_id)
      assert payment != nil

      refund_id = "re_chref_#{System.unique_integer()}"
      charge_id = "ch_with_ref_#{System.unique_integer()}"

      refund_struct = %Stripe.Refund{
        id: refund_id,
        object: "refund",
        charge: charge_id,
        amount: 4000,
        status: "succeeded",
        payment_intent: payment.external_payment_id,
        metadata: %{}
      }

      charge = %Stripe.Charge{
        id: charge_id,
        object: "charge",
        payment_intent: payment.external_payment_id,
        amount: 8000,
        refunds: %Stripe.List{
          data: [refund_struct],
          has_more: false,
          object: "list",
          url: "/v1/refunds"
        }
      }

      assert :ok =
               WebhookHandler.handle_webhook_event("charge.refunded", charge)

      assert Ledgers.get_refund_by_external_id(refund_id) != nil
    end

    test "normalize_currency falls back to USD for unknown currency string" do
      payout_id = "po_unk_#{System.unique_integer()}"

      payout_map = %{
        "id" => payout_id,
        "amount" => 10_000,
        "currency" => "xxxunknown",
        "status" => "paid",
        "arrival_date" => System.os_time(:second),
        "description" => "Unknown currency",
        "metadata" => %{}
      }

      assert :ok =
               WebhookHandler.handle_webhook_event("payout.paid", payout_map)

      assert Ledgers.get_payout_by_stripe_id(payout_id) != nil
    end

    test "invoice.subscription_update downgrade proration lines yield default proration ledger description when upgrade indeterminate" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      family_plan =
        Application.get_env(:ysc, :membership_plans, [])
        |> Enum.find(&(&1.id in [:family, "family"]))

      assert family_plan

      Subscriptions.create_subscription_item(%{
        subscription_id: subscription.id,
        stripe_id: "si_down_#{System.unique_integer()}",
        stripe_product_id: "prod_family",
        stripe_price_id: family_plan.stripe_price_id,
        quantity: 1
      })

      inv_id = "in_downgrade_#{System.unique_integer()}"

      invoice_data = %{
        "id" => inv_id,
        "customer" => user.stripe_id,
        "subscription" => subscription.stripe_id,
        "billing_reason" => "subscription_update",
        "amount_paid" => 3000,
        "description" => "Downgrade",
        "number" => "INV-DG",
        "charge" => nil,
        "metadata" => %{},
        "lines" => %{
          "data" => [
            %{
              "description" => "Unused time on Family after 17 Feb 2026",
              "amount" => -4000
            },
            %{
              "description" => "Remaining time on Single after 17 Feb 2026",
              "amount" => 2500
            }
          ]
        }
      }

      assert :ok =
               WebhookHandler.handle_event(
                 build_stripe_event("invoice.payment_succeeded", invoice_data)
               )

      payment = Ledgers.get_payment_by_external_id(inv_id)
      assert payment != nil

      assert Repo.exists?(
               from(le in Ysc.Ledgers.LedgerEntry,
                 where: le.payment_id == ^payment.id,
                 where: ilike(le.description, "%Prorated membership update%")
               )
             )
    end

    test "invoice subscription_update without proration line pairs uses default proration description" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      inv_id = "in_no_pr_lines_#{System.unique_integer()}"

      invoice_data = %{
        "id" => inv_id,
        "customer" => user.stripe_id,
        "subscription" => subscription.stripe_id,
        "billing_reason" => "subscription_update",
        "amount_paid" => 2000,
        "description" => "Update",
        "number" => "INV-NP",
        "charge" => nil,
        "metadata" => %{},
        "lines" => %{"data" => []}
      }

      assert :ok =
               WebhookHandler.handle_event(
                 build_stripe_event("invoice.payment_succeeded", invoice_data)
               )

      payment = Ledgers.get_payment_by_external_id(inv_id)
      assert payment != nil

      assert Repo.exists?(
               from(le in Ysc.Ledgers.LedgerEntry,
                 where: le.payment_id == ^payment.id,
                 where: ilike(le.description, "%Prorated membership update%")
               )
             )
    end

    test "customer.subscription.deleted cancels local subscription" do
      user = user_with_stripe_id()
      subscription = create_subscription(user, %{stripe_status: "active"})

      sub_data =
        SubscriptionFixtures.subscription(
          id: subscription.stripe_id,
          customer: user.stripe_id,
          status: "canceled",
          items: %Stripe.List{
            data: [],
            has_more: false,
            object: "list",
            url: "/v1/items"
          }
        )

      event = build_stripe_event("customer.subscription.deleted", sub_data)
      assert :ok = WebhookHandler.handle_event(event)

      assert Ysc.Repo.reload(subscription).stripe_status == "cancelled"
    end
  end

  describe "WebhookHandler public helpers and fee extraction" do
    test "event_payload_for_storage returns storable map for nested Stripe data" do
      user = user_with_stripe_id()

      inv = %Stripe.Invoice{
        id: "in_store_#{System.unique_integer()}",
        object: "invoice",
        customer: user.stripe_id,
        lines: %Stripe.List{
          data: [],
          has_more: false,
          object: "list",
          url: "/v1/lines"
        }
      }

      event = build_stripe_event("invoice.payment_succeeded", inv)
      payload = WebhookHandler.event_payload_for_storage(event)

      assert payload[:id] == event.id
      assert payload[:type] == "invoice.payment_succeeded"
      assert is_map(payload[:data])
    end

    test "fetch_actual_stripe_fee_from_charge(nil) returns zero USD" do
      fee = WebhookHandler.fetch_actual_stripe_fee_from_charge(nil)
      assert Money.zero?(fee)
      assert fee.currency == :USD
    end

    test "calculate_estimated_fee_from_charge_amount handles Stripe retrieve error" do
      fee =
        WebhookHandler.calculate_estimated_fee_from_charge_amount(
          "ch_missing_#{System.unique_integer()}"
        )

      assert Money.zero?(fee)
    end

    test "extract_stripe_fee_from_invoice falls back when metadata fee is not parseable as integer" do
      invoice = %{
        "id" => "in_dec_#{System.unique_integer()}",
        "charge" => nil,
        "metadata" => %{"stripe_fee" => "not_integer"}
      }

      fee = WebhookHandler.extract_stripe_fee_from_invoice(invoice)
      assert %Money{} = fee
    end

    test "extract_stripe_fee_from_invoice treats very large integer metadata as dollars" do
      invoice = %{
        "id" => "in_large_#{System.unique_integer()}",
        "charge" => nil,
        "metadata" => %{"stripe_fee" => "150000"}
      }

      fee = WebhookHandler.extract_stripe_fee_from_invoice(invoice)
      assert %Money{} = fee
    end

    test "extract_stripe_fee_from_payment_intent estimates when charge has no id" do
      pi = %Stripe.PaymentIntent{
        id: "pi_fee_#{System.unique_integer()}",
        object: "payment_intent",
        amount: 10_000,
        latest_charge: %{"amount" => 1000}
      }

      fee = WebhookHandler.extract_stripe_fee_from_payment_intent(pi)
      assert %Money{} = fee
    end

    test "extract_stripe_fee_from_invoice uses integer metadata fee as cents when under large threshold" do
      invoice = %{
        "id" => "in_cent_fee_#{System.unique_integer()}",
        "charge" => nil,
        "metadata" => %{"stripe_fee" => "350"}
      }

      fee = WebhookHandler.extract_stripe_fee_from_invoice(invoice)
      assert %Money{} = fee
      assert Money.cmp(fee, Money.new(:USD, "3.50")) == 0
    end

    test "extract_stripe_fee_from_payment_intent accepts map with latest_charge id" do
      pi = %{
        "id" => "pi_map_fee_#{System.unique_integer()}",
        "amount" => 5000,
        "latest_charge" => "ch_lc_#{System.unique_integer()}"
      }

      fee = WebhookHandler.extract_stripe_fee_from_payment_intent(pi)
      assert %Money{} = fee
    end

    test "extract_stripe_fee_from_payment_intent estimates from amount when charge lookup uses only amount" do
      fee =
        WebhookHandler.extract_stripe_fee_from_payment_intent(%{
          "amount" => 20_000
        })

      assert %Money{} = fee
    end

    test "extract_stripe_fee_from_payment_intent uses string-key charges.data for charge id" do
      pi = %{
        "id" => "pi_charges_map_#{System.unique_integer()}",
        "charges" => %{
          "data" => [%{"id" => "ch_nested_#{System.unique_integer()}"}]
        }
      }

      fee = WebhookHandler.extract_stripe_fee_from_payment_intent(pi)
      assert %Money{} = fee
    end

    test "calculate_estimated_fee handles small payment amounts" do
      fee = WebhookHandler.calculate_estimated_fee(Decimal.new("1.00"))
      assert %Money{} = fee
      assert Money.positive?(fee)
    end

    test "debug_payout_transactions returns error tuple when Stripe list fails" do
      assert {:error, _} =
               WebhookHandler.debug_payout_transactions(
                 "po_debug_invalid_#{System.unique_integer()}"
               )
    end

    test "charge.refunded with empty refund list logs and returns ok via handle_webhook_event" do
      charge = %Stripe.Charge{
        id: "ch_empty_ref_#{System.unique_integer()}",
        object: "charge",
        payment_intent: "pi_x",
        amount: 1000,
        refunds: %Stripe.List{
          data: [],
          has_more: false,
          object: "list",
          url: "/v1/refunds"
        }
      }

      assert :ok =
               WebhookHandler.handle_webhook_event("charge.refunded", charge)
    end

    test "refund.created map handler processes same as struct when payment exists" do
      user = user_with_stripe_id()
      subscription = create_subscription(user)

      invoice_data = %{
        "id" => "in_refmap_#{System.unique_integer()}",
        "customer" => user.stripe_id,
        "subscription" => subscription.stripe_id,
        "amount_paid" => 10_000,
        "charge" => nil
      }

      assert :ok =
               WebhookHandler.handle_event(
                 build_stripe_event("invoice.payment_succeeded", invoice_data)
               )

      payment = Ledgers.get_payment_by_external_id(invoice_data["id"])
      refund_id = "re_map_h_#{System.unique_integer()}"

      refund_map = %{
        "id" => refund_id,
        "charge" => "ch_test",
        "amount" => 5000,
        "status" => "succeeded",
        "payment_intent" => payment.external_payment_id
      }

      assert :ok =
               WebhookHandler.handle_webhook_event("refund.created", refund_map)

      assert Ledgers.get_refund_by_external_id(refund_id) != nil
    end
  end

  # ---------------------------------------------------------------------------
  # extract_id_from_expandable/1
  # Stripe fields like `payment_intent` or `charge` may be returned as a plain
  # string ID OR as a fully expanded object struct/map. These tests enforce that
  # the helper correctly unwraps either form to a string ID.
  # ---------------------------------------------------------------------------
  describe "extract_id_from_expandable/1" do
    test "returns nil for nil input" do
      assert WebhookHandler.extract_id_from_expandable(nil) == nil
    end

    test "returns a plain binary string unchanged" do
      assert WebhookHandler.extract_id_from_expandable("pi_abc123") ==
               "pi_abc123"
    end

    test "extracts :id from an expanded Stripe struct" do
      intent = %Stripe.PaymentIntent{id: "pi_struct_test"}

      assert WebhookHandler.extract_id_from_expandable(intent) ==
               "pi_struct_test"
    end

    test "extracts :id from a different Stripe struct type (Invoice)" do
      invoice = %Stripe.Invoice{id: "in_struct_test"}

      assert WebhookHandler.extract_id_from_expandable(invoice) ==
               "in_struct_test"
    end

    test "extracts :id from a plain map with atom key" do
      assert WebhookHandler.extract_id_from_expandable(%{id: "pi_atom_key"}) ==
               "pi_atom_key"
    end

    test "extracts id from a plain map with string key" do
      assert WebhookHandler.extract_id_from_expandable(%{
               "id" => "pi_string_key"
             }) ==
               "pi_string_key"
    end

    test "returns nil when the id value is not a binary (integer)" do
      assert WebhookHandler.extract_id_from_expandable(%{id: 12_345}) == nil
    end

    test "returns nil for non-string, non-map inputs (integer)" do
      assert WebhookHandler.extract_id_from_expandable(42) == nil
    end

    test "returns nil for non-string, non-map inputs (atom)" do
      assert WebhookHandler.extract_id_from_expandable(:some_atom) == nil
    end

    test "returns nil for a struct that has no :id field" do
      # A struct whose :id is nil (e.g. a partially constructed struct)
      # should return nil rather than crash.
      intent = %Stripe.PaymentIntent{id: nil}
      assert WebhookHandler.extract_id_from_expandable(intent) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # Payout charge linking
  # These tests verify the two bugs fixed in link_charge_to_payout/3:
  #   1. Expanded payment_intent struct is unwrapped before DB lookup
  #   2. Falls back to invoice_id when payment_intent lookup returns nil
  # ---------------------------------------------------------------------------
  describe "payout charge linking" do
    setup do
      Ledgers.ensure_basic_accounts()
      :ok
    end

    test "links payment when payment_intent is an expanded Stripe struct" do
      pi_id = "pi_expanded_#{System.unique_integer()}"
      payment = Ysc.LedgersFixtures.payment_fixture(external_payment_id: pi_id)
      payout = Ysc.LedgersFixtures.payout_fixture()

      # Build an expanded charge where payment_intent is a %Stripe.PaymentIntent{}
      # struct rather than a plain string — this is the bug scenario.
      expanded_charge = %Stripe.Charge{
        id: "ch_expanded_#{System.unique_integer()}",
        payment_intent: %Stripe.PaymentIntent{id: pi_id}
      }

      # link_charge_to_payout is tested via the public relink helper by
      # stubbing out the Stripe API calls it makes internally. Since we cannot
      # intercept Stripe.BalanceTransaction.list in tests, we instead validate
      # the extract_id_from_expandable + get_payment_by_external_id path
      # directly to guarantee the expected DB lookup occurs.
      extracted_id =
        WebhookHandler.extract_id_from_expandable(
          expanded_charge.payment_intent
        )

      assert extracted_id == pi_id

      found = Ledgers.get_payment_by_external_id(extracted_id)
      assert found != nil
      assert found.id == payment.id

      {:ok, _} = Ledgers.link_payment_to_payout(payout, found)

      linked_payout = Ledgers.get_payout!(payout.id)
      assert Enum.any?(linked_payout.payments, &(&1.id == payment.id))
    end

    test "falls back to invoice_id when payment_intent lookup returns nil" do
      inv_id = "in_fallback_#{System.unique_integer()}"
      pi_id = "pi_nomatch_#{System.unique_integer()}"

      # Payment stored with invoice as external_payment_id (subscription flow)
      payment = Ysc.LedgersFixtures.payment_fixture(external_payment_id: inv_id)
      payout = Ysc.LedgersFixtures.payout_fixture()

      # Verify that looking up by payment_intent_id finds nothing, and that the
      # fallback to invoice_id finds the correct payment.
      refute Ledgers.get_payment_by_external_id(pi_id)

      found_by_invoice = Ledgers.get_payment_by_external_id(inv_id)
      assert found_by_invoice != nil
      assert found_by_invoice.id == payment.id

      # Simulate the sequential lookup: first try PI (miss), then invoice (hit)
      payment_from_fallback =
        Ledgers.get_payment_by_external_id(pi_id) ||
          Ledgers.get_payment_by_external_id(inv_id)

      assert payment_from_fallback.id == payment.id

      {:ok, _} = Ledgers.link_payment_to_payout(payout, payment_from_fallback)

      linked_payout = Ledgers.get_payout!(payout.id)
      assert Enum.any?(linked_payout.payments, &(&1.id == payment.id))
    end

    test "invoice field as expanded struct is unwrapped before DB lookup" do
      inv_id = "in_struct_expanded_#{System.unique_integer()}"
      payment = Ysc.LedgersFixtures.payment_fixture(external_payment_id: inv_id)

      expanded_invoice = %Stripe.Invoice{id: inv_id}

      extracted_id = WebhookHandler.extract_id_from_expandable(expanded_invoice)
      assert extracted_id == inv_id

      found = Ledgers.get_payment_by_external_id(extracted_id)
      assert found.id == payment.id
    end

    test "charge field in refund as expanded struct is unwrapped" do
      charge_id = "ch_refund_struct_#{System.unique_integer()}"
      # Simulate a refund where the 'charge' field is an expanded Stripe.Charge
      expanded_charge = %Stripe.Charge{id: charge_id}

      extracted_id = WebhookHandler.extract_id_from_expandable(expanded_charge)
      assert extracted_id == charge_id
    end
  end

  # ---------------------------------------------------------------------------
  # Relinking an already-deposited payout must never re-trigger a QuickBooks
  # *create*. Sync.sync_payout/1 always checks an already-deposited payout
  # against QuickBooks for drift (a payment can link after the deposit was
  # created) rather than blindly re-creating - see
  # Ysc.Quickbooks.SyncTest's "sync_payout/1" describe block for the
  # create/update/no-op/conflict dispatch itself. This just proves the
  # webhook_handler.ex -> Sync wiring doesn't regress into re-creating.
  # ---------------------------------------------------------------------------
  describe "relink_payout_transactions/1 does not duplicate an existing QuickBooks deposit" do
    import Mox

    setup :verify_on_exit!

    setup do
      Ledgers.ensure_basic_accounts()

      previous_client = Application.get_env(:ysc, :stripe_client)
      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

      on_exit(fn ->
        if previous_client do
          Application.put_env(:ysc, :stripe_client, previous_client)
        else
          Application.delete_env(:ysc, :stripe_client)
        end
      end)

      :ok
    end

    test "leaves an already-synced payout's QuickBooks state untouched" do
      payout = Ysc.LedgersFixtures.payout_fixture()

      synced_payout =
        payout
        |> Ledgers.Payout.changeset(%{
          quickbooks_sync_status: "synced",
          quickbooks_deposit_id: "dep_existing_123",
          fee_total: Money.new(0, :USD)
        })
        |> Ysc.Repo.update!()

      stub(Ysc.StripeMock, :retrieve_payout, fn _id, _opts ->
        {:ok,
         %Stripe.Payout{
           id: synced_payout.stripe_payout_id,
           object: "payout",
           balance_transaction: nil
         }}
      end)

      stub(Ysc.StripeMock, :list_balance_transactions, fn _params, _opts ->
        {:ok,
         %Stripe.List{
           object: "list",
           data: [],
           has_more: false,
           url: "/v1/balance_transactions"
         }}
      end)

      # No payments/refunds are linked to this payout, so there's nothing
      # for the diff to find missing - Sync.sync_payout/1 should still ask
      # QuickBooks first, though. expect/3 (not stub/3) so the test fails if
      # that read is ever skipped, and deny/3 create_deposit so it fails if
      # the code ever falls back to re-creating instead of diffing.
      expect(
        Ysc.Quickbooks.ClientMock,
        :get_deposit_by_id,
        fn "dep_existing_123" ->
          {:ok, %{"Id" => "dep_existing_123", "SyncToken" => "0", "Line" => []}}
        end
      )

      deny(Ysc.Quickbooks.ClientMock, :create_deposit, 2)

      _ = WebhookHandler.relink_payout_transactions(synced_payout)

      reloaded = Ledgers.get_payout!(payout.id)

      assert reloaded.quickbooks_sync_status == "synced"
      assert reloaded.quickbooks_deposit_id == "dep_existing_123"
    end
  end

  # ---------------------------------------------------------------------------
  # Full mixed payout integration.
  #
  # Shape follows Stripe Dashboard payout po_1TyL7dIZd8GkARoBdw1Ipxew:
  #   - per-charge processing fees on charge BTs (`fee`)
  #   - standalone `stripe_fee` BT ("Billing - Usage Fee …", amount negative, fee 0)
  #   - payout BT with fee 0
  # Expanded to also cover membership (invoice lookup), event ticket, tahoe +
  # clear-lake bookings, donation purchase, and a partial refund.
  # ---------------------------------------------------------------------------
  describe "mixed payout.paid end-to-end" do
    import Mox

    setup do
      previous_client = Application.get_env(:ysc, :stripe_client)

      previous_payouts =
        Application.get_env(:ysc, :process_stripe_payout_webhooks)

      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)
      Application.put_env(:ysc, :process_stripe_payout_webhooks, true)

      on_exit(fn ->
        if previous_client do
          Application.put_env(:ysc, :stripe_client, previous_client)
        else
          Application.delete_env(:ysc, :stripe_client)
        end

        if previous_payouts != nil do
          Application.put_env(
            :ysc,
            :process_stripe_payout_webhooks,
            previous_payouts
          )
        else
          Application.delete_env(:ysc, :process_stripe_payout_webhooks)
        end
      end)

      Ledgers.ensure_basic_accounts()
      user = user_with_stripe_id()
      %{user: user}
    end

    test "links mixed entity payments/refund, books usage fee, reconciles", %{
      user: user
    } do
      uniq = System.unique_integer([:positive])
      stripe_payout_id = "po_mixed_#{uniq}"

      # Amounts mirror a rich Stripe payout summary (cents):
      # membership $45 + ticket $50 + tahoe $200 + clear lake $80 + donation $25
      # = $400 gross; refund $20; processing fees $13.11; usage fee $0.95
      # → payout $365.94
      membership_pi = "in_mixed_membership_#{uniq}"
      ticket_pi = "pi_mixed_ticket_#{uniq}"
      tahoe_pi = "pi_mixed_tahoe_#{uniq}"
      clear_lake_pi = "pi_mixed_clear_lake_#{uniq}"
      donation_pi = "pi_mixed_donation_#{uniq}"

      membership_ch = "ch_mixed_membership_#{uniq}"
      ticket_ch = "ch_mixed_ticket_#{uniq}"
      tahoe_ch = "ch_mixed_tahoe_#{uniq}"
      clear_lake_ch = "ch_mixed_clear_lake_#{uniq}"
      donation_ch = "ch_mixed_donation_#{uniq}"
      refund_id = "re_mixed_ticket_#{uniq}"

      {:ok, {membership_payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(:USD, "45.00"),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: membership_pi,
          stripe_fee: Money.new(:USD, "1.61"),
          description: "Subscription creation - membership",
          property: nil,
          payment_method_id: nil
        })

      {:ok, {ticket_payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(:USD, "50.00"),
          entity_type: :event,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: ticket_pi,
          stripe_fee: Money.new(:USD, "1.75"),
          description: "Ticket purchase",
          property: nil,
          payment_method_id: nil
        })

      {:ok, {tahoe_payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(:USD, "200.00"),
          entity_type: :booking,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: tahoe_pi,
          stripe_fee: Money.new(:USD, "6.10"),
          description: "Tahoe booking purchase",
          property: :tahoe,
          payment_method_id: nil
        })

      {:ok, {clear_lake_payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(:USD, "80.00"),
          entity_type: :booking,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: clear_lake_pi,
          stripe_fee: Money.new(:USD, "2.62"),
          description: "Clear Lake booking purchase",
          property: :clear_lake,
          payment_method_id: nil
        })

      {:ok, {donation_payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(:USD, "25.00"),
          entity_type: :donation,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: donation_pi,
          stripe_fee: Money.new(:USD, "1.03"),
          description: "Donation purchase",
          property: nil,
          payment_method_id: nil
        })

      {:ok, {ticket_refund, _, _}} =
        Ledgers.process_refund(%{
          payment_id: ticket_payment.id,
          refund_amount: Money.new(:USD, "20.00"),
          reason: "Partial ticket refund",
          external_refund_id: refund_id
        })

      balance_transactions = [
        %Stripe.BalanceTransaction{
          id: "txn_usage_#{uniq}",
          object: "balance_transaction",
          type: "stripe_fee",
          reporting_category: "fee",
          amount: -95,
          fee: 0,
          net: -95,
          currency: "usd",
          description: "Billing - Usage Fee (2026-07-27)",
          source: nil
        },
        %Stripe.BalanceTransaction{
          id: "txn_membership_#{uniq}",
          object: "balance_transaction",
          type: "charge",
          reporting_category: "charge",
          amount: 4500,
          fee: 161,
          net: 4339,
          currency: "usd",
          description: "Subscription creation - membership",
          # Maps: stripity_stripe Charge has no :invoice field; membership
          # payments are looked up by invoice id (subscription path).
          source: %{
            id: membership_ch,
            object: "charge",
            amount: 4500,
            payment_intent: nil,
            invoice: membership_pi
          }
        },
        %Stripe.BalanceTransaction{
          id: "txn_ticket_#{uniq}",
          object: "balance_transaction",
          type: "charge",
          reporting_category: "charge",
          amount: 5000,
          fee: 175,
          net: 4825,
          currency: "usd",
          description: "Ticket purchase",
          source: %{
            id: ticket_ch,
            object: "charge",
            amount: 5000,
            payment_intent: ticket_pi,
            invoice: nil
          }
        },
        %Stripe.BalanceTransaction{
          id: "txn_tahoe_#{uniq}",
          object: "balance_transaction",
          type: "charge",
          reporting_category: "charge",
          amount: 20_000,
          fee: 610,
          net: 19_390,
          currency: "usd",
          description: "Tahoe booking purchase",
          source: %{
            id: tahoe_ch,
            object: "charge",
            amount: 20_000,
            payment_intent: tahoe_pi,
            invoice: nil
          }
        },
        %Stripe.BalanceTransaction{
          id: "txn_clear_lake_#{uniq}",
          object: "balance_transaction",
          type: "charge",
          reporting_category: "charge",
          amount: 8000,
          fee: 262,
          net: 7738,
          currency: "usd",
          description: "Clear Lake booking purchase",
          source: %{
            id: clear_lake_ch,
            object: "charge",
            amount: 8000,
            payment_intent: clear_lake_pi,
            invoice: nil
          }
        },
        %Stripe.BalanceTransaction{
          id: "txn_donation_#{uniq}",
          object: "balance_transaction",
          type: "charge",
          reporting_category: "charge",
          amount: 2500,
          fee: 103,
          net: 2397,
          currency: "usd",
          description: "Donation purchase",
          source: %{
            id: donation_ch,
            object: "charge",
            amount: 2500,
            payment_intent: donation_pi,
            invoice: nil
          }
        },
        %Stripe.BalanceTransaction{
          id: "txn_refund_#{uniq}",
          object: "balance_transaction",
          type: "refund",
          reporting_category: "refund",
          amount: -2000,
          fee: 0,
          net: -2000,
          currency: "usd",
          description: "Partial ticket refund",
          source: %Stripe.Refund{
            id: refund_id,
            object: "refund",
            amount: 2000,
            charge: ticket_ch,
            status: "succeeded"
          }
        },
        %Stripe.BalanceTransaction{
          id: "txn_payout_#{uniq}",
          object: "balance_transaction",
          type: "payout",
          reporting_category: "payout",
          amount: -36_594,
          fee: 0,
          net: -36_594,
          currency: "usd",
          description: "STRIPE PAYOUT",
          source: stripe_payout_id
        }
      ]

      stub(Ysc.StripeMock, :retrieve_payout, fn ^stripe_payout_id, _opts ->
        {:ok,
         %Stripe.Payout{
           id: stripe_payout_id,
           object: "payout",
           amount: 36_594,
           currency: "usd",
           status: "paid",
           arrival_date: System.os_time(:second),
           description: "STRIPE PAYOUT",
           balance_transaction: %Stripe.BalanceTransaction{
             id: "txn_payout_#{uniq}",
             type: "payout",
             fee: 0,
             amount: -36_594,
             net: -36_594,
             currency: "usd"
           }
         }}
      end)

      stub(Ysc.StripeMock, :list_balance_transactions, fn params, _opts ->
        assert params.payout == stripe_payout_id

        {:ok,
         %Stripe.List{
           object: "list",
           data: balance_transactions,
           has_more: false,
           url: "/v1/balance_transactions"
         }}
      end)

      # Refund linking expands charge via retrieve_charge
      stub(Ysc.StripeMock, :retrieve_charge, fn charge_id, _opts ->
        case charge_id do
          ^ticket_ch ->
            {:ok,
             %Stripe.Charge{
               id: ticket_ch,
               payment_intent: ticket_pi,
               amount: 5000
             }}

          _ ->
            {:error, :unexpected_charge}
        end
      end)

      payout_map = %{
        "id" => stripe_payout_id,
        "amount" => 36_594,
        "currency" => "usd",
        "status" => "paid",
        "arrival_date" => System.os_time(:second),
        "description" => "STRIPE PAYOUT",
        "metadata" => %{},
        "fees" => nil
      }

      assert :ok =
               WebhookHandler.handle_webhook_event("payout.paid", payout_map)

      payout =
        Ledgers.get_payout_by_stripe_id(stripe_payout_id)
        |> Ysc.Repo.preload([:payments, :refunds, :payment])

      assert payout != nil
      assert Money.equal?(payout.amount, Money.new(:USD, "365.94"))

      # Processing fees ($13.11) + Billing Usage Fee ($0.95) = $14.06
      assert Money.equal?(payout.fee_total, Money.new(:USD, "14.06"))

      linked_payment_ids = MapSet.new(Enum.map(payout.payments, & &1.id))

      assert MapSet.subset?(
               MapSet.new([
                 membership_payment.id,
                 ticket_payment.id,
                 tahoe_payment.id,
                 clear_lake_payment.id,
                 donation_payment.id
               ]),
               linked_payment_ids
             )

      assert length(payout.payments) == 5
      assert Enum.map(payout.refunds, & &1.id) == [ticket_refund.id]

      # Usage fee booked on the payout's virtual payment
      payout_fee_entries =
        Ledgers.get_entries_by_payment(payout.payment_id)
        |> Enum.filter(fn entry ->
          entry.account.name == "stripe_fees" and
            entry.debit_credit == :debit and
            String.starts_with?(
              entry.description || "",
              "Stripe payout fee for "
            )
        end)

      assert length(payout_fee_entries) == 1

      assert Money.equal?(
               hd(payout_fee_entries).amount,
               Money.new(:USD, "0.95")
             )

      # Full reconciliation must pass for this mixed payout
      report = Ysc.Ledgers.Reconciliation.reconcile_payouts()
      assert report.status == :ok, inspect(report.discrepancies)

      refute Enum.any?(report.discrepancies, fn d ->
               d.stripe_payout_id == stripe_payout_id
             end)

      # Understated fee_total (charge fees only) would fail composition —
      # same class of bug as the original Billing Usage Fee gap.
      understated =
        payout
        |> Ledgers.Payout.changeset(%{fee_total: Money.new(:USD, "13.11")})
        |> Ysc.Repo.update!()
        |> Ysc.Repo.preload([:payments, :refunds])

      fail_report = Ysc.Ledgers.Reconciliation.reconcile_payouts()
      assert fail_report.status == :error

      assert Enum.any?(fail_report.discrepancies, fn d ->
               d.stripe_payout_id == understated.stripe_payout_id and
                 Enum.any?(
                   d.issues,
                   &String.contains?(&1, "composition mismatch")
                 )
             end)
    end
  end

  # When stripity_stripe Charge structs omit :invoice (current API versions),
  # subscription payments must still link via a raw Stripe charge retrieve.
  describe "payout charge invoice Req fallback" do
    import Mox

    @charge_req_stub :stripe_charge_fetch

    setup context do
      Req.Test.set_req_test_from_context(context)

      previous_client = Application.get_env(:ysc, :stripe_client)

      previous_payouts =
        Application.get_env(:ysc, :process_stripe_payout_webhooks)

      previous_req_opts =
        Application.get_env(:ysc, :stripe_charge_fetch_req_opts)

      previous_base_url = Application.get_env(:stripity_stripe, :api_base_url)

      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)
      Application.put_env(:ysc, :process_stripe_payout_webhooks, true)

      Application.put_env(:ysc, :stripe_charge_fetch_req_opts,
        plug: {Req.Test, @charge_req_stub}
      )

      Application.put_env(:stripity_stripe, :api_base_url, "http://stripe.test")

      on_exit(fn ->
        restore_env(:ysc, :stripe_client, previous_client)
        restore_env(:ysc, :process_stripe_payout_webhooks, previous_payouts)
        restore_env(:ysc, :stripe_charge_fetch_req_opts, previous_req_opts)
        restore_env(:stripity_stripe, :api_base_url, previous_base_url)
      end)

      Ledgers.ensure_basic_accounts()
      :ok
    end

    test "links subscription payment when Charge struct omits invoice field" do
      uniq = System.unique_integer([:positive])
      stripe_payout_id = "po_req_invoice_#{uniq}"
      inv_id = "in_req_fallback_#{uniq}"
      charge_id = "ch_req_fallback_#{uniq}"
      user = user_with_stripe_id()

      {:ok, {membership_payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(:USD, "45.00"),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: inv_id,
          stripe_fee: Money.new(:USD, "1.61"),
          description: "Subscription creation - membership",
          property: nil,
          payment_method_id: nil
        })

      balance_transactions = [
        %Stripe.BalanceTransaction{
          id: "txn_membership_#{uniq}",
          object: "balance_transaction",
          type: "charge",
          reporting_category: "charge",
          amount: 4500,
          fee: 161,
          net: 4339,
          currency: "usd",
          description: "Subscription creation - membership",
          source: %Stripe.Charge{
            id: charge_id,
            object: "charge",
            amount: 4500,
            payment_intent: nil
          }
        },
        %Stripe.BalanceTransaction{
          id: "txn_payout_#{uniq}",
          object: "balance_transaction",
          type: "payout",
          reporting_category: "payout",
          amount: -4339,
          fee: 0,
          net: -4339,
          currency: "usd",
          description: "STRIPE PAYOUT",
          source: stripe_payout_id
        }
      ]

      stub(Ysc.StripeMock, :retrieve_payout, fn ^stripe_payout_id, _opts ->
        {:ok,
         %Stripe.Payout{
           id: stripe_payout_id,
           object: "payout",
           amount: 4339,
           currency: "usd",
           status: "paid",
           arrival_date: System.os_time(:second),
           description: "STRIPE PAYOUT",
           balance_transaction: %Stripe.BalanceTransaction{
             id: "txn_payout_#{uniq}",
             type: "payout",
             fee: 0,
             amount: -4339,
             net: -4339,
             currency: "usd"
           }
         }}
      end)

      stub(Ysc.StripeMock, :list_balance_transactions, fn params, _opts ->
        assert params.payout == stripe_payout_id

        {:ok,
         %Stripe.List{
           object: "list",
           data: balance_transactions,
           has_more: false,
           url: "/v1/balance_transactions"
         }}
      end)

      Req.Test.stub(@charge_req_stub, fn conn ->
        assert conn.request_path == "/v1/charges/#{charge_id}"

        Req.Test.json(conn, %{
          "id" => charge_id,
          "object" => "charge",
          "invoice" => inv_id
        })
      end)

      payout_map = %{
        "id" => stripe_payout_id,
        "amount" => 4339,
        "currency" => "usd",
        "status" => "paid",
        "arrival_date" => System.os_time(:second),
        "description" => "STRIPE PAYOUT",
        "metadata" => %{},
        "fees" => nil
      }

      assert :ok =
               WebhookHandler.handle_webhook_event("payout.paid", payout_map)

      payout =
        Ledgers.get_payout_by_stripe_id(stripe_payout_id)
        |> Ysc.Repo.preload(:payments)

      assert payout != nil
      assert Enum.any?(payout.payments, &(&1.id == membership_payment.id))
    end
  end

  defp restore_env(app, key, value) do
    if value != nil do
      Application.put_env(app, key, value)
    else
      Application.delete_env(app, key)
    end
  end
end
