defmodule Ysc.Stripe.DonationPaymentLink do
  @moduledoc """
  Books donations paid through a configured Stripe Payment Link.

  A Payment Link opens a Checkout Session. `checkout.session.completed` and
  `checkout.session.async_payment_succeeded` include `payment_link`. This module
  retrieves that link and, when its public URL is configured, records the
  payment as donation revenue.

  The ledger payment is keyed by the PaymentIntent id. Payout linking and
  refunds already look payments up that way, and `Ledgers.process_payment/1`
  enqueues the QuickBooks sales receipt. Each link names its own income
  account. `https://donate.stripe.com/28E5kEaLcg63aPW6nr2Ji03` posts to
  Tahoe Kitchen Fund, not Special Project Fundraising. Donors whose email
  matches a member are attached to that user; everyone else is exported on
  the QuickBooks system customer.
  """

  require Ysc.Logging

  alias Ysc.Accounts
  alias Ysc.Ledgers
  alias Ysc.MoneyHelper
  alias Ysc.Stripe.WebhookHandler

  @ledger_marker "Stripe payment link donation"
  @fund_separator " | "
  @tahoe_kitchen_fund_url "https://donate.stripe.com/28E5kEaLcg63aPW6nr2Ji03"

  @doc """
  Returns true when a ledger entry was booked from a Stripe donation Payment Link.
  """
  def payment_link_donation_entry?(%{description: description})
      when is_binary(description) do
    String.contains?(description, @ledger_marker)
  end

  def payment_link_donation_entry?(_), do: false

  @doc """
  Income account and QuickBooks class for a payment-link donation entry.

  The account is taken from the ledger description, which names the fund for
  the Payment Link that was paid. `nil` when the entry is not one of these
  donations or does not name a fund.
  """
  def payment_link_fund(%{description: description})
      when is_binary(description) do
    marker = @ledger_marker <> @fund_separator

    with [_, rest] <- String.split(description, marker, parts: 2),
         fund <-
           rest
           |> String.split(@fund_separator, parts: 2)
           |> hd()
           |> String.trim(),
         true <- fund != "" do
      %{account: fund, class: "Administration"}
    else
      _ -> nil
    end
  end

  def payment_link_fund(_), do: nil

  @doc """
  Books a paid Checkout Session when it belongs to a configured donation link.

  Returns `:ok`. Raises when the session is a configured donation but Stripe or
  the ledger cannot be updated, so the webhook is marked failed and retried.
  """
  def book_paid_session(session) when is_map(session) do
    if session_value(session, :payment_status) == "paid" do
      maybe_book_configured_link(session)
    else
      :ok
    end
  end

  defp maybe_book_configured_link(session) do
    case payment_link_id(session) do
      id when is_binary(id) ->
        book_if_configured(session, id)

      _ ->
        :ok
    end
  end

  defp book_if_configured(session, payment_link_id) do
    configured = configured_identifiers()

    if configured == [] do
      :ok
    else
      case retrieve_payment_link(payment_link_id) do
        {:ok, link} ->
          case matching_configured_link(link, configured) do
            nil ->
              :ok

            configured_link ->
              book_donation(session, payment_link_id, configured_link)
          end

        {:error, reason} ->
          Ysc.Logging.error(
            "Failed to retrieve Stripe payment link for donation checkout",
            payment_link_id: payment_link_id,
            checkout_session_id: session_value(session, :id),
            error: inspect(reason)
          )

          raise "Failed to retrieve Stripe payment link #{payment_link_id}: #{inspect(reason)}"
      end
    end
  end

  defp book_donation(session, payment_link_id, configured_link) do
    session_id = session_value(session, :id)

    payment_intent_id =
      WebhookHandler.extract_id_from_expandable(
        session_value(session, :payment_intent)
      )

    amount_cents = session_value(session, :amount_total)
    currency = session_value(session, :currency) || "usd"

    cond do
      not is_binary(payment_intent_id) ->
        raise "Donation checkout session #{session_id} has no payment intent"

      currency != "usd" ->
        raise "Donation checkout session #{session_id} currency #{currency} is not USD"

      not is_integer(amount_cents) or amount_cents <= 0 ->
        Ysc.Logging.warning(
          "Skipping donation checkout session with no positive amount",
          checkout_session_id: session_id,
          payment_link_id: payment_link_id,
          amount_total: amount_cents
        )

        :ok

      true ->
        insert_donation(
          session,
          payment_link_id,
          configured_link,
          payment_intent_id,
          amount_cents
        )
    end
  end

  defp insert_donation(
         session,
         payment_link_id,
         configured_link,
         payment_intent_id,
         amount_cents
       ) do
    {name, email} = donor_identity(session)
    user = if email, do: Accounts.get_user_by_email(email), else: nil
    amount = MoneyHelper.cents_to_money(amount_cents, :USD)
    description = donation_description(name, email, configured_link.account)

    case Ledgers.process_payment(%{
           user_id: user && user.id,
           amount: amount,
           entity_type: :donation,
           entity_id: nil,
           external_payment_id: payment_intent_id,
           stripe_fee: stripe_fee(payment_intent_id),
           description: description,
           property: nil,
           payment_method_id: nil
         }) do
      {:ok, {payment, _transaction, _entries}} ->
        Ysc.Logging.info("Booked Stripe payment link donation",
          checkout_session_id: session_value(session, :id),
          payment_link_id: payment_link_id,
          payment_intent_id: payment_intent_id,
          payment_id: payment.id,
          user_id: payment.user_id,
          amount: Money.to_string!(amount),
          quickbooks_account: configured_link.account
        )

        :ok

      {:error, reason} ->
        Ysc.Logging.error("Failed to book Stripe payment link donation",
          checkout_session_id: session_value(session, :id),
          payment_link_id: payment_link_id,
          payment_intent_id: payment_intent_id,
          error: inspect(reason)
        )

        raise "Failed to book Stripe payment link donation: #{inspect(reason)}"
    end
  end

  defp stripe_fee(payment_intent_id) do
    case stripe_client().retrieve_payment_intent(payment_intent_id, %{
           expand: ["latest_charge"]
         }) do
      {:ok, payment_intent} ->
        WebhookHandler.extract_stripe_fee_from_payment_intent(payment_intent)

      {:error, reason} ->
        Ysc.Logging.error(
          "Failed to retrieve payment intent for donation fee",
          payment_intent_id: payment_intent_id,
          error: inspect(reason)
        )

        raise "Failed to retrieve payment intent #{payment_intent_id} for donation fee: #{inspect(reason)}"
    end
  end

  defp donor_identity(session) do
    details = session_value(session, :customer_details) || %{}

    email =
      one_line(session_value(details, :email)) ||
        one_line(session_value(session, :customer_email))

    {one_line(session_value(details, :name)), email}
  end

  defp donation_description(name, email, account) do
    who =
      cond do
        is_binary(name) and is_binary(email) -> "#{name} <#{email}>"
        is_binary(email) -> email
        is_binary(name) -> name
        true -> nil
      end

    fund = "#{@ledger_marker}#{@fund_separator}#{account}"

    case who do
      nil -> fund
      who -> "#{fund}#{@fund_separator}from #{who}"
    end
  end

  defp matching_configured_link(link, configured) do
    case session_value(link, :url) do
      url when is_binary(url) ->
        normalized = normalize_url(url)
        slug = slug_from_url(normalized)

        Enum.find(configured, fn configured_link ->
          configured_link.normalized == normalized or
            (slug != "" and configured_link.slug == slug)
        end)

      _ ->
        nil
    end
  end

  defp configured_identifiers do
    :ysc
    |> Application.get_env(:stripe_donation_payment_links, [])
    |> configured_links()
  end

  defp configured_links(config) when is_list(config) do
    links = Keyword.get(config, :links, [])
    urls = Keyword.get(config, :urls, [])

    (links ++ urls)
    |> Enum.map(&normalize_configured_link/1)
    |> Enum.reject(&is_nil/1)
  end

  defp configured_links(_), do: []

  defp normalize_configured_link(%{url: url} = link) when is_binary(url) do
    known = known_link(url)
    account = present_string(link[:account]) || (known && known.account)

    if account do
      %{
        url: url,
        account: account,
        normalized: normalize_url(url),
        slug: slug_from_url(normalize_url(url))
      }
    else
      nil
    end
  end

  defp normalize_configured_link(url) when is_binary(url) do
    normalize_configured_link(%{url: url})
  end

  defp normalize_configured_link(_), do: nil

  # This donate link raises money for the Tahoe kitchen. A URL-only config
  # entry still posts to that fund.
  defp known_link(url) when is_binary(url) do
    normalized = normalize_url(url)
    slug = slug_from_url(normalized)

    if normalized == normalize_url(@tahoe_kitchen_fund_url) or
         slug == slug_from_url(normalize_url(@tahoe_kitchen_fund_url)) do
      %{account: "Tahoe Kitchen Fund"}
    else
      nil
    end
  end

  defp present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present_string(_), do: nil

  defp normalize_url(url) when is_binary(url) do
    url =
      url
      |> String.trim()
      |> String.split("?", parts: 2)
      |> hd()
      |> String.trim_trailing("/")

    case URI.parse(url) do
      %URI{scheme: scheme, host: host, path: path} when is_binary(host) ->
        scheme =
          if is_binary(scheme), do: String.downcase(scheme), else: "https"

        "#{scheme}://#{String.downcase(host)}#{path || ""}"

      _ ->
        url
    end
  end

  defp slug_from_url(url) when is_binary(url) do
    path =
      case URI.parse(url) do
        %URI{path: path} when is_binary(path) and path != "" -> path
        _ -> url
      end

    path
    |> String.trim("/")
    |> String.split("/")
    |> List.last()
    |> case do
      slug when is_binary(slug) -> slug
      _ -> ""
    end
  end

  defp payment_link_id(session) do
    WebhookHandler.extract_id_from_expandable(
      session_value(session, :payment_link)
    )
  end

  defp retrieve_payment_link(id) do
    client = stripe_client()

    # function_exported?/3 is false until the module is loaded.
    if Code.ensure_loaded?(client) and
         function_exported?(client, :retrieve_payment_link, 1) do
      client.retrieve_payment_link(id)
    else
      {:error, :retrieve_payment_link_not_implemented}
    end
  end

  defp stripe_client do
    Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)
  end

  defp session_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp session_value(_, _), do: nil

  defp one_line(value) when is_binary(value) do
    case value |> String.replace(~r/[\r\n]+/, " ") |> String.trim() do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp one_line(_), do: nil
end
