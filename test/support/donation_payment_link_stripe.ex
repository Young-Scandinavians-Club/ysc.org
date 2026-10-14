defmodule Ysc.Stripe.DonationPaymentLinkTestClient do
  @moduledoc false

  @tahoe_url "https://donate.stripe.com/28E5kEaLcg63aPW6nr2Ji03"

  def retrieve_payment_link("plink_tahoe_kitchen") do
    {:ok, %{id: "plink_tahoe_kitchen", url: @tahoe_url}}
  end

  def retrieve_payment_link("plink_other") do
    {:ok, %{id: "plink_other", url: "https://buy.stripe.com/not-a-donation"}}
  end

  def retrieve_payment_link(id), do: {:error, {:not_found, id}}

  # No expanded charge, so the donation books an estimated fee instead of
  # calling retrieve_charge.
  def retrieve_payment_intent(id, _opts) when is_binary(id) do
    {:ok, %{id: id, amount: 5_000}}
  end
end
