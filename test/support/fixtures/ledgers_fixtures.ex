defmodule Ysc.LedgersFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ysc.Ledgers` context.
  """

  alias Ysc.Ledgers

  def payment_fixture(attrs \\ %{}) do
    user_id = attrs[:user_id] || Ysc.AccountsFixtures.user_fixture().id

    {:ok, {payment, _transaction, _entries}} =
      attrs
      |> Enum.into(%{
        user_id: user_id,
        amount: Money.new(100, :USD),
        entity_type: :event,
        entity_id: Ecto.ULID.generate(),
        external_payment_id: "pi_test_#{System.unique_integer()}",
        stripe_fee: Money.new(320, :USD),
        description: "Test payment",
        property: nil,
        payment_method_id: nil
      })
      |> Ledgers.process_payment()

    payment
  end

  def refund_fixture(attrs \\ %{}) do
    payment = attrs[:payment] || payment_fixture()

    {:ok, {refund, _transaction, _entries}} =
      attrs
      |> Enum.into(%{
        payment_id: payment.id,
        refund_amount: Money.new(50, :USD),
        external_refund_id: "re_test_#{System.unique_integer()}",
        reason: "Test refund"
      })
      |> Ledgers.process_refund()

    refund
  end

  def payout_fixture(attrs \\ %{}) do
    {:ok, {_payout_payment, _transaction, _entries, payout}} =
      attrs
      |> Enum.into(%{
        payout_amount: Money.new(1000, :USD),
        stripe_payout_id: "po_test_#{System.unique_integer()}",
        description: "Test payout",
        currency: "usd",
        status: "paid",
        arrival_date: DateTime.utc_now(),
        metadata: %{}
      })
      |> Ledgers.process_stripe_payout()

    payout
  end
end
