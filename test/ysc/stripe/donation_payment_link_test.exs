defmodule Ysc.Stripe.DonationPaymentLinkTest do
  use Ysc.DataCase, async: false

  import Ecto.Query

  alias Ysc.Ledgers
  alias Ysc.Ledgers.Payment
  alias Ysc.Repo
  alias Ysc.Stripe.DonationPaymentLink
  alias Ysc.Stripe.WebhookHandler

  setup do
    Ledgers.ensure_basic_accounts()
    Cachex.clear(:ysc_cache)
    previous = Application.get_env(:ysc, :stripe_client)

    Application.put_env(
      :ysc,
      :stripe_client,
      Ysc.Stripe.DonationPaymentLinkTestClient
    )

    on_exit(fn ->
      if previous do
        Application.put_env(:ysc, :stripe_client, previous)
      else
        Application.delete_env(:ysc, :stripe_client)
      end
    end)

    :ok
  end

  test "books the donate.stripe.com link against Tahoe Kitchen Fund" do
    assert :ok = book_session("plink_tahoe_kitchen", "pi_tahoe_kitchen")

    payment = Repo.get_by!(Payment, external_payment_id: "pi_tahoe_kitchen")
    assert Money.equal?(payment.amount, Money.new(50, :USD))

    assert DonationPaymentLink.payment_link_fund(payment) == %{
             account: "Tahoe Kitchen Fund",
             class: "Administration"
           }
  end

  test "books the same payment intent once without another fee lookup" do
    assert :ok = book_session("plink_tahoe_kitchen", "pi_tahoe_once")
    assert_received {:retrieve_payment_link, "plink_tahoe_kitchen"}
    assert_received {:retrieve_payment_intent, "pi_tahoe_once"}

    assert :ok = book_session("plink_tahoe_kitchen", "pi_tahoe_once")
    refute_received {:retrieve_payment_link, "plink_tahoe_kitchen"}
    refute_received {:retrieve_payment_intent, "pi_tahoe_once"}

    count =
      Repo.aggregate(
        from(p in Payment, where: p.external_payment_id == "pi_tahoe_once"),
        :count
      )

    assert count == 1
  end

  test "books checkout.session.async_payment_succeeded" do
    assert :ok =
             WebhookHandler.handle_webhook_event(
               "checkout.session.async_payment_succeeded",
               session("plink_tahoe_kitchen", "pi_async", "paid")
             )

    payment = Repo.get_by!(Payment, external_payment_id: "pi_async")

    assert DonationPaymentLink.payment_link_fund(payment).account ==
             "Tahoe Kitchen Fund"
  end

  test "books a donor who is not a member without a user" do
    assert :ok =
             WebhookHandler.handle_webhook_event(
               "checkout.session.completed",
               session("plink_tahoe_kitchen", "pi_guest", "paid", %{
                 "email" => "guest-donor@example.com",
                 "name" => "Guest Donor"
               })
             )

    payment = Repo.get_by!(Payment, external_payment_id: "pi_guest")
    assert payment.user_id == nil

    assert payment.metadata["quickbooks_income_account"] ==
             "Tahoe Kitchen Fund"
  end

  test "skips a non-USD donation instead of retrying the webhook" do
    assert :ok =
             WebhookHandler.handle_webhook_event(
               "checkout.session.completed",
               session("plink_tahoe_kitchen", "pi_eur", "paid")
               |> Map.put("currency", "eur")
             )

    refute Repo.get_by(Payment, external_payment_id: "pi_eur")
  end

  test "skips a paid session that has no payment intent" do
    assert :ok =
             WebhookHandler.handle_webhook_event(
               "checkout.session.completed",
               session("plink_tahoe_kitchen", "pi_missing_intent", "paid")
               |> Map.put("payment_intent", nil)
             )

    refute Repo.get_by(Payment, external_payment_id: "pi_missing_intent")
  end

  test "raises when the payment link cannot be retrieved" do
    assert_raise RuntimeError, ~r/plink_missing/, fn ->
      book_session("plink_missing", "pi_stripe_down")
    end

    refute Repo.get_by(Payment, external_payment_id: "pi_stripe_down")
  end

  test "skips when the stripe client cannot retrieve payment links" do
    Application.put_env(:ysc, :stripe_client, Ysc.TestStripeClient)

    assert :ok = book_session("plink_tahoe_kitchen", "pi_no_callback")
    refute Repo.get_by(Payment, external_payment_id: "pi_no_callback")
  end

  test "ignores a payment link that is not a configured donation" do
    assert :ok = book_session("plink_other", "pi_other_link")
    refute Repo.get_by(Payment, external_payment_id: "pi_other_link")
  end

  test "does not book an unpaid checkout session" do
    assert :ok =
             WebhookHandler.handle_webhook_event(
               "checkout.session.completed",
               session("plink_tahoe_kitchen", "pi_unpaid", "unpaid")
             )

    refute Repo.get_by(Payment, external_payment_id: "pi_unpaid")
  end

  defp book_session(payment_link_id, payment_intent_id) do
    WebhookHandler.handle_webhook_event(
      "checkout.session.completed",
      session(payment_link_id, payment_intent_id, "paid")
    )
  end

  defp session(
         payment_link_id,
         payment_intent_id,
         payment_status,
         customer_details \\ nil
       ) do
    %{
      "id" => "cs_#{payment_intent_id}",
      "object" => "checkout.session",
      "payment_status" => payment_status,
      "payment_link" => payment_link_id,
      "payment_intent" => payment_intent_id,
      "amount_total" => 5_000,
      "currency" => "usd",
      "customer_details" =>
        customer_details ||
          %{
            "email" => "ada@example.com",
            "name" => "Ada Lovelace"
          }
    }
  end
end
