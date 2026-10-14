defmodule Ysc.Stripe.DonationPaymentLinkTest do
  use Ysc.DataCase, async: false

  import Ecto.Query

  alias Ysc.Ledgers
  alias Ysc.Ledgers.LedgerEntry
  alias Ysc.Ledgers.Payment
  alias Ysc.Repo
  alias Ysc.Stripe.DonationPaymentLink
  alias Ysc.Stripe.WebhookHandler

  setup do
    Ledgers.ensure_basic_accounts()
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

    fund =
      payment.id
      |> ledger_entries()
      |> Enum.find_value(&DonationPaymentLink.payment_link_fund/1)

    assert fund == %{account: "Tahoe Kitchen Fund", class: "Administration"}
  end

  test "books the same payment intent once" do
    assert :ok = book_session("plink_tahoe_kitchen", "pi_tahoe_once")
    assert :ok = book_session("plink_tahoe_kitchen", "pi_tahoe_once")

    count =
      Repo.aggregate(
        from(p in Payment, where: p.external_payment_id == "pi_tahoe_once"),
        :count
      )

    assert count == 1
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

  defp session(payment_link_id, payment_intent_id, payment_status) do
    %{
      "id" => "cs_#{payment_intent_id}",
      "object" => "checkout.session",
      "payment_status" => payment_status,
      "payment_link" => payment_link_id,
      "payment_intent" => payment_intent_id,
      "amount_total" => 5_000,
      "currency" => "usd",
      "customer_details" => %{
        "email" => "ada@example.com",
        "name" => "Ada Lovelace"
      }
    }
  end

  defp ledger_entries(payment_id) do
    Repo.all(from e in LedgerEntry, where: e.payment_id == ^payment_id)
  end
end
