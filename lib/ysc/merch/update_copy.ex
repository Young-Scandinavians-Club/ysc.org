defmodule Ysc.Merch.UpdateCopy do
  @moduledoc """
  Member-facing wording for merch order updates, shared by the email and SMS
  templates so the two channels never disagree.

  Kinds: `:delivered`, `:returned`, `:failed`, `:canceled`.
  """

  @kinds [:delivered, :returned, :failed, :canceled]

  def kinds, do: @kinds

  @doc "Email headline and paragraphs for `kind`."
  @spec email(atom(), boolean()) :: {String.t(), [String.t()]}
  def email(:delivered, _comp?) do
    {"Your order was delivered",
     [
       "Tracking shows your order as delivered. We hope you love it!",
       "If anything isn't right, just reply to this email or write to info@ysc.org and we'll sort it out."
     ]}
  end

  def email(:returned, _comp?) do
    {"Your package came back to us",
     [
       "Your package was returned to the sender, usually because of an address problem or a missed delivery.",
       "Please email info@ysc.org and we'll get it to you."
     ]}
  end

  def email(:failed, comp?) do
    {"There's a problem with your order",
     [
       "We couldn't start making your order, so it hasn't been made or shipped.",
       "The club has been alerted and will follow up with you. " <>
         make_it_right(comp?)
     ]}
  end

  def email(:canceled, comp?) do
    {"Your order was canceled",
     [
       "Your order has been canceled, so nothing will be shipped.",
       make_it_right(comp?) <> " Questions? Email info@ysc.org."
     ]}
  end

  defp make_it_right(true), do: "There's nothing to pay for this order."

  defp make_it_right(false),
    do: "If you were charged, you'll get a full refund."

  @doc "Short SMS text for `kind` (no greeting or prefix)."
  @spec sms(atom(), String.t()) :: String.t()
  def sms(:delivered, ref),
    do: "Your YSC order #{ref} was delivered. Enjoy!"

  def sms(:returned, ref),
    do:
      "Your YSC order #{ref} was returned to sender. Email info@ysc.org and we'll sort it out."

  def sms(:failed, ref),
    do:
      "There's a problem with your YSC order #{ref}. The club will be in touch; questions: info@ysc.org."

  def sms(:canceled, ref),
    do: "Your YSC order #{ref} was canceled. Questions: info@ysc.org."
end
