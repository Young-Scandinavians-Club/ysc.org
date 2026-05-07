defmodule YscWeb.PaymentMethodLogo do
  @moduledoc false

  # Maps normalized payment types / card brands to files under priv/static/images/cards/

  @spec path_for_payment(term()) :: String.t() | nil
  def path_for_payment(nil), do: nil

  def path_for_payment(%{payment_method: nil}), do: nil

  def path_for_payment(%{payment_method: pm}) do
    path_for_db_payment_method(pm)
  end

  def path_for_payment(_), do: nil

  defp path_for_db_payment_method(pm) do
    type = pm.type

    cond do
      type == :link ->
        file("link.png")

      type == :card ->
        card_brand_to_file(pm.display_brand)

      true ->
        alternative_type_to_file(type)
    end
  end

  @spec path_for_stripe_summary(atom(), String.t() | nil) :: String.t() | nil
  def path_for_stripe_summary(:link, _), do: file("link.png")

  def path_for_stripe_summary(:card, display_brand),
    do: card_brand_to_file(display_brand)

  def path_for_stripe_summary(:bank_account, _), do: nil
  def path_for_stripe_summary(:us_bank_account, _), do: nil
  def path_for_stripe_summary(:sepa_debit, _), do: nil
  def path_for_stripe_summary(:cashapp, _), do: file("cashapp.svg")
  def path_for_stripe_summary(:paypal, _), do: file("paypal.svg")
  def path_for_stripe_summary(:klarna, _), do: file("klarna.svg")
  def path_for_stripe_summary(:amazon_pay, _), do: file("amazon.svg")
  def path_for_stripe_summary(:affirm, _), do: file("affirm.svg")
  def path_for_stripe_summary(:apple_pay, _), do: file("apple.svg")
  def path_for_stripe_summary(:google_pay, _), do: file("google.svg")
  def path_for_stripe_summary(_, _), do: nil

  defp alternative_type_to_file(:link), do: file("link.png")
  defp alternative_type_to_file(:cashapp), do: file("cashapp.svg")
  defp alternative_type_to_file(:paypal), do: file("paypal.svg")
  defp alternative_type_to_file(:klarna), do: file("klarna.svg")
  defp alternative_type_to_file(:amazon_pay), do: file("amazon.svg")
  defp alternative_type_to_file(:affirm), do: file("affirm.svg")
  defp alternative_type_to_file(:apple_pay), do: file("apple.svg")
  defp alternative_type_to_file(:google_pay), do: file("google.svg")
  defp alternative_type_to_file(_), do: nil

  defp card_brand_to_file(nil), do: nil

  defp card_brand_to_file(brand) when is_binary(brand) do
    brand
    |> String.downcase()
    |> String.replace(" ", "_")
    |> map_brand_string()
  end

  defp map_brand_string("visa"), do: file("visa.png")
  defp map_brand_string("mastercard"), do: file("mc.svg")
  defp map_brand_string("mc"), do: file("mc.svg")
  defp map_brand_string("amex"), do: file("amex.svg")
  defp map_brand_string("american_express"), do: file("amex.svg")
  defp map_brand_string("discover"), do: file("discover.svg")
  defp map_brand_string("diners"), do: file("diners.svg")
  defp map_brand_string("diners_club"), do: file("diners.svg")
  defp map_brand_string("jcb"), do: file("jcb.svg")
  defp map_brand_string("unionpay"), do: file("unionpay.svg")
  defp map_brand_string(_), do: nil

  defp file(name), do: "/images/cards/#{name}"
end
