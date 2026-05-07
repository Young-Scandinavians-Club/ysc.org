defmodule YscWeb.PaymentMethodFormatter do
  @moduledoc false

  def normalize_payment_type(type) when is_atom(type), do: type

  def normalize_payment_type(type) when is_binary(type) do
    case type do
      "card" -> :card
      "us_bank_account" -> :bank_account
      "bank_account" -> :bank_account
      "sepa_debit" -> :sepa_debit
      "link" -> :link
      "paypal" -> :paypal
      "affirm" -> :affirm
      "klarna" -> :klarna
      "cashapp" -> :cashapp
      "amazon_pay" -> :amazon_pay
      "apple_pay" -> :apple_pay
      "google_pay" -> :google_pay
      _ -> :other
    end
  end

  def normalize_payment_type(_), do: :other

  def extract_payment_method_details(stripe_pm) do
    base_type = stripe_pm_base_type_string(stripe_pm)
    actual_type = resolve_stripe_string_actual_type(base_type, stripe_pm)
    last_four = extract_stripe_pm_last_four_for_type(base_type, stripe_pm)

    display_brand =
      extract_stripe_pm_display_brand_for_type(base_type, stripe_pm)

    {actual_type, last_four, display_brand}
  end

  def stripe_pm_base_type_string(stripe_pm) do
    Map.get(stripe_pm, :type) || Map.get(stripe_pm, "type")
  end

  def resolve_stripe_string_actual_type("card", stripe_pm) do
    card = Map.get(stripe_pm, :card) || Map.get(stripe_pm, "card")

    if card do
      wallet = Map.get(card, :wallet) || Map.get(card, "wallet")

      if wallet do
        wallet_type = Map.get(wallet, :type) || Map.get(wallet, "type")

        case wallet_type do
          "link" -> "link"
          _ -> "card"
        end
      else
        brand = Map.get(card, :brand) || Map.get(card, "brand")
        if brand == "link", do: "link", else: "card"
      end
    else
      "card"
    end
  end

  def resolve_stripe_string_actual_type(base_type, _stripe_pm), do: base_type

  def extract_stripe_pm_last_four_for_type("card", stripe_pm) do
    card = Map.get(stripe_pm, :card) || Map.get(stripe_pm, "card")

    if card do
      wallet = Map.get(card, :wallet) || Map.get(card, "wallet")

      if wallet do
        Map.get(wallet, :dynamic_last4) ||
          Map.get(wallet, "dynamic_last4") ||
          Map.get(card, :last4) ||
          Map.get(card, "last4")
      else
        Map.get(card, :last4) || Map.get(card, "last4")
      end
    else
      nil
    end
  end

  def extract_stripe_pm_last_four_for_type("us_bank_account", stripe_pm) do
    bank =
      Map.get(stripe_pm, :us_bank_account) ||
        Map.get(stripe_pm, "us_bank_account")

    if bank, do: Map.get(bank, :last4) || Map.get(bank, "last4"), else: nil
  end

  def extract_stripe_pm_last_four_for_type("link", stripe_pm) do
    link = Map.get(stripe_pm, :link) || Map.get(stripe_pm, "link")

    if link, do: Map.get(link, :last4) || Map.get(link, "last4"), else: nil
  end

  def extract_stripe_pm_last_four_for_type("cashapp", stripe_pm) do
    cashapp = Map.get(stripe_pm, :cashapp) || Map.get(stripe_pm, "cashapp")

    if cashapp,
      do: Map.get(cashapp, :last4) || Map.get(cashapp, "last4"),
      else: nil
  end

  def extract_stripe_pm_last_four_for_type(_, _), do: nil

  def extract_stripe_pm_display_brand_for_type("card", stripe_pm) do
    card = Map.get(stripe_pm, :card) || Map.get(stripe_pm, "card")

    if card do
      wallet = Map.get(card, :wallet) || Map.get(card, "wallet")

      if wallet do
        wallet_type = Map.get(wallet, :type) || Map.get(wallet, "type")

        case wallet_type do
          "link" -> card_display_brand(card)
          "apple_pay" -> "Apple Pay"
          "google_pay" -> "Google Pay"
          _ -> card_display_brand(card)
        end
      else
        card_display_brand(card)
      end
    else
      nil
    end
  end

  def extract_stripe_pm_display_brand_for_type("us_bank_account", stripe_pm) do
    bank =
      Map.get(stripe_pm, :us_bank_account) ||
        Map.get(stripe_pm, "us_bank_account")

    if bank,
      do: Map.get(bank, :bank_name) || Map.get(bank, "bank_name"),
      else: nil
  end

  def extract_stripe_pm_display_brand_for_type(_, _), do: nil

  def format_payment_method_with_details(type, last_four, display_brand) do
    case normalize_payment_type(type) do
      :card ->
        if last_four do
          brand = payment_brand_label(display_brand || "Card")
          "#{brand} ending in #{last_four}"
        else
          "Credit Card"
        end

      :link ->
        format_link_payment_method(last_four, display_brand)

      :bank_account ->
        if last_four do
          bank_name = display_brand || "Bank"
          "#{bank_name} Account ending in #{last_four}"
        else
          "Bank Account"
        end

      :us_bank_account ->
        if last_four do
          bank_name = display_brand || "Bank"
          "#{bank_name} Account ending in #{last_four}"
        else
          "Bank Account"
        end

      normalized_type ->
        payment_method =
          if last_four do
            %{last_four: last_four, display_brand: display_brand}
          else
            nil
          end

        format_alternative_payment_method(normalized_type, payment_method)
    end
  end

  def format_alternative_payment_method(type, payment_method)
      when is_atom(type) do
    case type do
      :klarna ->
        if payment_method && payment_method_field(payment_method, :last_four) do
          "Klarna ending in #{payment_method_field(payment_method, :last_four)}"
        else
          "Klarna"
        end

      :amazon_pay ->
        "Amazon Pay"

      :cashapp ->
        if payment_method && payment_method_field(payment_method, :last_four) do
          "Cash App ending in #{payment_method_field(payment_method, :last_four)}"
        else
          "Cash App"
        end

      :paypal ->
        "PayPal"

      :apple_pay ->
        "Apple Pay"

      :google_pay ->
        "Google Pay"

      :link ->
        last_four =
          payment_method && payment_method_field(payment_method, :last_four)

        display_brand =
          payment_method && payment_method_field(payment_method, :display_brand)

        format_link_payment_method(last_four, display_brand)

      :us_bank_account ->
        format_bank_account_payment_method(payment_method)

      :bank_account ->
        format_bank_account_payment_method(payment_method)

      :sepa_debit ->
        if payment_method && payment_method_field(payment_method, :last_four) do
          "SEPA Debit ending in #{payment_method_field(payment_method, :last_four)}"
        else
          "SEPA Debit"
        end

      :card ->
        if payment_method && payment_method_field(payment_method, :last_four) do
          brand =
            payment_brand_label(
              payment_method_field(payment_method, :display_brand) || "Card"
            )

          "#{brand} ending in #{payment_method_field(payment_method, :last_four)}"
        else
          "Credit Card"
        end

      _ ->
        type
        |> Atom.to_string()
        |> String.replace("_", " ")
        |> String.split()
        |> Enum.map_join(" ", &String.capitalize/1)
    end
  end

  def format_alternative_payment_method(type, payment_method)
      when is_binary(type) do
    type
    |> normalize_payment_type()
    |> format_alternative_payment_method(payment_method)
  end

  def format_alternative_payment_method(_, _), do: "Payment Method"

  def format_link_payment_method(last_four, display_brand) do
    card_brand =
      display_brand
      |> payment_brand_label()
      |> non_link_brand()

    cond do
      last_four && card_brand ->
        "Link · #{card_brand} ending in #{last_four}"

      last_four ->
        "Link ending in #{last_four}"

      card_brand ->
        "Link · #{card_brand}"

      true ->
        "Link"
    end
  end

  def card_display_brand(card) do
    Map.get(card, :display_brand) ||
      Map.get(card, "display_brand") ||
      Map.get(card, :brand) ||
      Map.get(card, "brand")
  end

  def payment_brand_label(nil), do: nil

  def payment_brand_label(brand) when is_binary(brand) do
    case String.downcase(brand) do
      "amex" ->
        "Amex"

      "american_express" ->
        "American Express"

      "mastercard" ->
        "Mastercard"

      "visa" ->
        "Visa"

      "link" ->
        "Link"

      _ ->
        brand
        |> String.replace("_", " ")
        |> String.split(" ", trim: true)
        |> Enum.map_join(" ", &String.capitalize/1)
    end
  end

  def non_link_brand("Link"), do: nil
  def non_link_brand(brand), do: brand

  defp format_bank_account_payment_method(payment_method) do
    if payment_method && payment_method_field(payment_method, :last_four) do
      bank_name =
        payment_method_field(payment_method, :bank_name) ||
          payment_method_field(payment_method, :display_brand) ||
          "Bank"

      "#{bank_name} Account ending in #{payment_method_field(payment_method, :last_four)}"
    else
      "Bank Account"
    end
  end

  defp payment_method_field(payment_method, field) do
    Map.get(payment_method, field) ||
      Map.get(payment_method, Atom.to_string(field))
  end
end
