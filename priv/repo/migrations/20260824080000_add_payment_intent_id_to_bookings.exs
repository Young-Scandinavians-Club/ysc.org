defmodule Ysc.Repo.Migrations.AddPaymentIntentIdToBookings do
  @moduledoc """
  Stores the Stripe PaymentIntent id on cabin bookings.

  ## Problem

  Releasing a hold called `Stripe.PaymentIntent.list(limit: 100)` inside the
  inventory transaction and scanned the results in Elixir for matching
  `metadata.booking_id`. Hold expiry and `confirm_booking/1` (sibling holds)
  did this once per booking, even when checkout never created a PaymentIntent.

  ## Solution

  Persist `payment_intent_id` when checkout creates the intent, then cancel by
  id after the inventory transaction commits.
  """
  use Ecto.Migration

  def change do
    alter table(:bookings) do
      add :payment_intent_id, :string
    end

    create unique_index(:bookings, [:payment_intent_id],
             where: "payment_intent_id IS NOT NULL",
             name: :bookings_payment_intent_id_index
           )
  end
end
