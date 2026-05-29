defmodule YscWeb.PaymentMethodFormatter do
  @moduledoc false

  alias Ysc.Stripe.PaymentIntentHelpers

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

  @doc """
  Reads card brand and last four from a Charge's `payment_method_details`.
  Link and wallet payments often only expose these fields on the charge, not on
  the PaymentMethod object.
  """
  def extract_payment_method_details_from_charge(charge) when is_map(charge) do
    pmd =
      Map.get(charge, :payment_method_details) ||
        Map.get(charge, "payment_method_details")

    card = pmd && (Map.get(pmd, :card) || Map.get(pmd, "card"))

    if card do
      wallet = Map.get(card, :wallet) || Map.get(card, "wallet")

      last_four =
        if wallet do
          Map.get(wallet, :dynamic_last4) ||
            Map.get(wallet, "dynamic_last4") ||
            Map.get(card, :last4) ||
            Map.get(card, "last4")
        else
          Map.get(card, :last4) || Map.get(card, "last4")
        end

      wallet_type =
        wallet && (Map.get(wallet, :type) || Map.get(wallet, "type"))

      actual_type =
        case wallet_type do
          "link" -> "link"
          _ -> "card"
        end

      brand = card_display_brand(card)
      {actual_type, last_four, brand}
    else
      extract_link_details_from_charge_pmd(pmd)
    end
  end

  def extract_payment_method_details_from_charge(_), do: {nil, nil, nil}

  defp extract_link_details_from_charge_pmd(pmd) when is_map(pmd) do
    pmd_type = Map.get(pmd, :type) || Map.get(pmd, "type")

    if pmd_type == "link" do
      link = Map.get(pmd, :link) || Map.get(pmd, "link")

      last4 =
        if link, do: Map.get(link, :last4) || Map.get(link, "last4"), else: nil

      {"link", last4, link && link_contact_display(link)}
    else
      {nil, nil, nil}
    end
  end

  defp extract_link_details_from_charge_pmd(_), do: {nil, nil, nil}

  @doc false
  def payment_details_from_payment_intent(payment_intent, stripe_client) do
    from_pm =
      payment_details_from_intent_payment_method(payment_intent, stripe_client)

    from_charge =
      payment_details_from_intent_charge(payment_intent, stripe_client)

    prefer_payment_details(from_pm, from_charge)
  end

  defp prefer_payment_details(pm_details, charge_details) do
    cond do
      payment_details_has_last_four?(pm_details) ->
        pm_details

      payment_details_has_last_four?(charge_details) ->
        charge_details

      true ->
        pick_richer_payment_details(pm_details, charge_details)
    end
  end

  defp payment_details_has_last_four?({_, last_four, _})
       when is_binary(last_four) and last_four != "",
       do: true

  defp payment_details_has_last_four?(_), do: false

  defp pick_richer_payment_details(pm_details, charge_details) do
    case {payment_details_display_rank(pm_details),
          payment_details_display_rank(charge_details)} do
      {_, 0} ->
        pm_details

      {0, _} ->
        charge_details

      {pm_rank, charge_rank} when charge_rank > pm_rank ->
        charge_details

      _ ->
        pm_details
    end
  end

  defp payment_details_display_rank({_, _, display}) do
    link_display_rank(display)
  end

  defp payment_details_from_intent_payment_method(payment_intent, stripe_client) do
    pm =
      Map.get(payment_intent, :payment_method) ||
        Map.get(payment_intent, "payment_method")

    cond do
      is_map(pm) && (Map.has_key?(pm, :type) || Map.has_key?(pm, "type")) ->
        extract_payment_method_details(pm)

      is_binary(pm) ->
        case stripe_client.retrieve_payment_method(pm) do
          {:ok, stripe_pm} -> extract_payment_method_details(stripe_pm)
          _ -> {nil, nil, nil}
        end

      true ->
        {nil, nil, nil}
    end
  end

  defp payment_details_from_intent_charge(payment_intent, stripe_client) do
    case PaymentIntentHelpers.first_expanded_charge(payment_intent) do
      charge when is_map(charge) ->
        extract_payment_method_details_from_charge(charge)

      _ ->
        case PaymentIntentHelpers.charge_id(payment_intent) do
          nil ->
            {nil, nil, nil}

          charge_id ->
            case stripe_client.retrieve_charge(charge_id, %{}) do
              {:ok, charge} ->
                extract_payment_method_details_from_charge(charge)

              _ ->
                {nil, nil, nil}
            end
        end
    end
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

  def extract_stripe_pm_display_brand_for_type("link", stripe_pm) do
    link = Map.get(stripe_pm, :link) || Map.get(stripe_pm, "link")
    link && link_display_identifier(link)
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

  @doc false
  def card_pan_mask(last_four) when is_binary(last_four),
    do: "**** **** **** #{last_four}"

  @doc false
  def format_receipt_card_payment_method(last_four, _display_brand) do
    if last_four do
      card_pan_mask(last_four)
    else
      "Credit Card"
    end
  end

  @doc false
  def format_receipt_link_payment_method(last_four, display_brand) do
    link_email = link_email_identifier(display_brand)

    card_brand =
      if link_email do
        nil
      else
        display_brand
        |> payment_brand_label()
        |> non_link_brand()
      end

    cond do
      last_four && card_brand ->
        "Link · #{card_brand} #{card_pan_mask(last_four)}"

      last_four ->
        "Link #{card_pan_mask(last_four)}"

      card_brand ->
        "Link · #{card_brand}"

      link_email ->
        "Link · #{link_email}"

      is_binary(display_brand) and display_brand != "" ->
        "Link · #{display_brand}"

      true ->
        "Link"
    end
  end

  @doc false
  def format_payment_method_for_receipt(type, last_four, display_brand) do
    case normalize_payment_type(type) do
      :card ->
        format_receipt_card_payment_method(last_four, display_brand)

      :link ->
        format_receipt_link_payment_method(last_four, display_brand)

      normalized_type ->
        format_payment_method_with_details(
          normalized_type,
          last_four,
          display_brand
        )
    end
  end

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

  defp link_display_identifier(link) when is_map(link) do
    link_contact_display(link) ||
      Map.get(link, :last4) || Map.get(link, "last4")
  end

  defp link_contact_display(link) when is_map(link) do
    Map.get(link, :email) || Map.get(link, "email") ||
      Map.get(link, :country) || Map.get(link, "country")
  end

  defp link_email_identifier(brand) when is_binary(brand) do
    if String.contains?(brand, "@"), do: brand, else: nil
  end

  defp link_email_identifier(_), do: nil

  defp link_display_rank(nil), do: 0

  defp link_display_rank(brand) when is_binary(brand) do
    cond do
      String.contains?(brand, "@") -> 3
      brand != "" -> 1
      true -> 0
    end
  end

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
