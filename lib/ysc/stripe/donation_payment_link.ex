defmodule Ysc.Stripe.DonationPaymentLink do
  @moduledoc """
  Books donations paid through a Stripe Payment Link.

  A Payment Link opens a Checkout Session. `checkout.session.completed` and
  `checkout.session.async_payment_succeeded` include `payment_link`. This module
  retrieves that link (expanding `line_items.data.price.product`) and, when it
  is a donation link, records the payment as donation revenue.

  A link is recognized as a donation link when:
  - Its URL or slug matches an entry in `:stripe_donation_payment_links`,
  - `submit_type` is `"donate"` on the PaymentLink or Checkout.Session,
  - Its public URL is hosted on `donate.stripe.com`, or
  - Metadata on the session, link, or product defines `"quickbooks_income_account"`.

  The QuickBooks income account is resolved (in priority order) from:
  1. Explicit `:account` in `:stripe_donation_payment_links` config,
  2. `"quickbooks_income_account"` metadata on the session, payment link, or product,
  3. The Stripe Product name on the payment link's line item (e.g. `"Tahoe Kitchen Fund"`),
  4. Known link fallback for `https://donate.stripe.com/28E5kEaLcg63aPW6nr2Ji03`.

  The ledger payment is keyed by the PaymentIntent id. Payout linking and
  refunds already look payments up that way, and `Ledgers.process_payment/1`
  enqueues the QuickBooks sales receipt. Each donation stores its income
  account on `payment.metadata["quickbooks_income_account"]` and uses the
  Administration class. QuickBooks sync creates the income account and item
  automatically if they do not exist yet.
  """

  require Ysc.Logging

  alias Ysc.Accounts
  alias Ysc.Ledgers
  alias Ysc.Ledgers.Payment
  alias Ysc.MoneyHelper
  alias Ysc.Stripe.WebhookHandler

  @ledger_marker "Stripe payment link donation"
  @fund_separator " | "
  @income_account_key "quickbooks_income_account"
  @tahoe_kitchen_fund_url "https://donate.stripe.com/28E5kEaLcg63aPW6nr2Ji03"
  @payment_link_expand %{expand: ["line_items.data.price.product"]}
  @payment_link_cache_ttl :timer.minutes(10)
  @checkout_events [
    "checkout.session.completed",
    "checkout.session.async_payment_succeeded"
  ]

  @doc """
  Returns true when a payment was booked from a Stripe donation Payment Link.
  """
  def payment_link_donation_entry?(%Payment{} = payment) do
    payment_link_fund(payment) != nil
  end

  def payment_link_donation_entry?(_), do: false

  @doc """
  Income account and QuickBooks class for a payment-link donation.

  The account is `metadata["quickbooks_income_account"]`. Every donation uses
  the Administration class. `nil` when the payment is not one of these donations.
  """
  def payment_link_fund(%{metadata: metadata}) when is_map(metadata) do
    account =
      present_string(Map.get(metadata, @income_account_key)) ||
        present_string(Map.get(metadata, :quickbooks_income_account))

    if account do
      %{account: account, class: "Administration"}
    else
      nil
    end
  end

  def payment_link_fund(_), do: nil

  @doc """
  Raises when a configured donation link has no QuickBooks income account.

  A `|Class` segment is ignored. Called from application startup.
  """
  def validate_configured_links! do
    raw = raw_configured_links()

    Enum.each(raw, fn link ->
      class = present_string(link_value(link, :class))

      if class do
        Ysc.Logging.warning(
          "Donation payment link class is ignored; donations use the Administration class",
          url: link_value(link, :url),
          class: class
        )
      end
    end)

    dropped =
      Enum.filter(raw, fn link ->
        url = link_value(link, :url)
        is_binary(url) and url != "" and is_nil(account_for_link(link))
      end)

    if dropped != [] do
      urls = Enum.map(dropped, &link_value(&1, :url))

      Ysc.Logging.error(
        "Donation payment links are missing a QuickBooks income account",
        urls: inspect(urls)
      )

      raise "Donation payment links need a QuickBooks income account: #{inspect(urls)}"
    end

    :ok
  end

  @doc """
  Fills the Payment Link and fee cache before the webhook database transaction.

  Booking still runs in the handler. A cache hit keeps those Stripe calls off
  the open transaction. Errors are left for the handler so the webhook is
  marked failed and retried.
  """
  def prefetch_paid_session(%{type: type, data: data})
      when type in @checkout_events do
    session = data_object(data)

    if is_map(session) do
      _ = warm_paid_session(session)
    end

    :ok
  rescue
    exception ->
      Ysc.Logging.warning(
        "Donation payment link prefetch failed; the webhook handler will retry it",
        error: Exception.message(exception)
      )

      :ok
  end

  def prefetch_paid_session(%{"type" => type, "data" => data})
      when type in @checkout_events do
    prefetch_paid_session(%{type: type, data: data})
  end

  def prefetch_paid_session(_), do: :ok

  @doc """
  Queues creation of the QuickBooks income account for a new or edited
  Payment Link. The webhook object has no expanded line items, so the job
  retrieves the link itself.
  """
  def enqueue_account_setup(payment_link) when is_map(payment_link) do
    case session_value(payment_link, :id) do
      id when is_binary(id) ->
        case %{"payment_link_id" => id}
             |> YscWeb.Workers.QuickbooksEnsureDonationAccountWorker.new()
             |> Oban.insert() do
          {:ok, _job} ->
            :ok

          {:error, reason} ->
            raise "Failed to enqueue account setup: #{inspect(reason)}"
        end

      _ ->
        :ok
    end
  end

  @doc """
  Creates the QuickBooks income account for a donation Payment Link when it
  does not exist yet.

  The account is the link's resolved fund (config, metadata, or Stripe product
  name). Returns `{:ok, account}`, `:skip` when the link is not a donation
  link, or `{:error, reason}` so the job retries. Always reads the link from
  Stripe, since a cached copy may predate the edit that triggered this call.
  """
  def ensure_quickbooks_account(payment_link_id)
      when is_binary(payment_link_id) do
    case fetch_payment_link(payment_link_id) do
      {:ok, link} ->
        case resolve_donation_link(%{}, link) do
          %{account: account} ->
            case Ysc.Quickbooks.Sync.ensure_income_account(account) do
              {:ok, _ref} -> {:ok, account}
              {:error, _reason} = error -> error
            end

          nil ->
            :skip
        end

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Books a paid Checkout Session when it belongs to a donation Payment Link.

  Returns `:ok`. Raises when the session is a donation link but Stripe or
  the ledger cannot be updated, so the webhook is marked failed and retried.
  """
  def book_paid_session(session) when is_map(session) do
    if session_value(session, :payment_status) == "paid" do
      maybe_book_donation_link(session)
    else
      :ok
    end
  end

  defp maybe_book_donation_link(session) do
    case payment_link_id(session) do
      id when is_binary(id) ->
        book_if_donation_link(session, id)

      _ ->
        :ok
    end
  end

  defp book_if_donation_link(session, payment_link_id) do
    case retrieve_payment_link(payment_link_id) do
      {:ok, link} ->
        case resolve_donation_link(session, link) do
          nil ->
            :ok

          resolved_link ->
            book_donation(session, payment_link_id, resolved_link)
        end

      {:error, :retrieve_payment_link_not_implemented} ->
        Ysc.Logging.error(
          "Stripe client cannot retrieve payment links; skipping donation checkout",
          payment_link_id: payment_link_id,
          checkout_session_id: session_value(session, :id)
        )

        :ok

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

  defp book_donation(session, payment_link_id, resolved_link) do
    session_id = session_value(session, :id)

    payment_intent_id =
      WebhookHandler.extract_id_from_expandable(
        session_value(session, :payment_intent)
      )

    amount_cents = session_value(session, :amount_total)
    currency = session_value(session, :currency) || "usd"

    cond do
      not is_binary(payment_intent_id) ->
        Ysc.Logging.error(
          "Skipping donation checkout session with no payment intent",
          checkout_session_id: session_id,
          payment_link_id: payment_link_id
        )

        :ok

      currency != "usd" ->
        Ysc.Logging.error(
          "Skipping donation checkout session that is not USD",
          checkout_session_id: session_id,
          payment_link_id: payment_link_id,
          currency: currency
        )

        :ok

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
          resolved_link,
          payment_intent_id,
          amount_cents
        )
    end
  end

  defp insert_donation(
         session,
         payment_link_id,
         resolved_link,
         payment_intent_id,
         amount_cents
       ) do
    case Ledgers.get_payment_by_external_id(payment_intent_id) do
      %Payment{} = existing ->
        Ysc.Logging.info("Stripe payment link donation already booked",
          checkout_session_id: session_value(session, :id),
          payment_link_id: payment_link_id,
          payment_intent_id: payment_intent_id,
          payment_id: existing.id
        )

        :ok

      nil ->
        book_new_donation(
          session,
          payment_link_id,
          resolved_link,
          payment_intent_id,
          amount_cents
        )
    end
  end

  defp book_new_donation(
         session,
         payment_link_id,
         resolved_link,
         payment_intent_id,
         amount_cents
       ) do
    {name, email} = donor_identity(session)
    user = if email, do: Accounts.get_user_by_email(email), else: nil
    amount = MoneyHelper.cents_to_money(amount_cents, :USD)
    description = donation_description(name, email, resolved_link.account)

    case Ledgers.process_payment(%{
           user_id: user && user.id,
           amount: amount,
           entity_type: :donation,
           entity_id: nil,
           external_payment_id: payment_intent_id,
           stripe_fee: cached_stripe_fee(payment_intent_id),
           description: description,
           property: nil,
           payment_method_id: nil,
           metadata: %{@income_account_key => resolved_link.account}
         }) do
      {:ok, {payment, _transaction, _entries}} ->
        Ysc.Logging.info("Booked Stripe payment link donation",
          checkout_session_id: session_value(session, :id),
          payment_link_id: payment_link_id,
          payment_intent_id: payment_intent_id,
          payment_id: payment.id,
          user_id: payment.user_id,
          amount: Money.to_string!(amount),
          quickbooks_account: resolved_link.account
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

  defp cached_stripe_fee(payment_intent_id) do
    key = fee_cache_key(payment_intent_id)

    case Cachex.get(:ysc_cache, key) do
      {:ok, %Money{} = fee} ->
        fee

      _ ->
        fee = stripe_fee(payment_intent_id)
        Cachex.put(:ysc_cache, key, fee, expire: @payment_link_cache_ttl)
        fee
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

  defp resolve_donation_link(session, link) do
    configured = matching_configured_link(link, configured_identifiers())

    if configured != nil or donation_payment_link?(session, link) do
      account =
        (configured && configured.account) ||
          metadata_income_account(session) ||
          metadata_income_account(link) ||
          product_income_account(link) ||
          product_income_account(session) ||
          known_link_account(link)

      case present_string(account) do
        account when is_binary(account) ->
          %{account: account, url: session_value(link, :url)}

        nil ->
          Ysc.Logging.warning(
            "Donation payment link has no product name or QuickBooks income account; skipping",
            payment_link_id: session_value(link, :id),
            url: session_value(link, :url)
          )

          nil
      end
    else
      Ysc.Logging.info(
        "Stripe payment link checkout is not a configured donation link; not booking",
        payment_link_id: session_value(link, :id),
        url: session_value(link, :url),
        submit_type: session_value(link, :submit_type),
        checkout_session_id: session_value(session, :id)
      )

      nil
    end
  end

  defp donation_payment_link?(session, link) do
    session_value(link, :submit_type) == "donate" or
      session_value(session, :submit_type) == "donate" or
      donate_stripe_url?(session_value(link, :url)) or
      metadata_income_account(session) != nil or
      metadata_income_account(link) != nil or
      product_metadata_income_account(link) != nil
  end

  defp donate_stripe_url?(url) when is_binary(url) do
    case URI.parse(String.trim(url)) do
      %URI{host: host} when is_binary(host) ->
        String.downcase(host) == "donate.stripe.com"

      _ ->
        false
    end
  end

  defp donate_stripe_url?(_), do: false

  defp metadata_income_account(map) when is_map(map) do
    case session_value(map, :metadata) do
      metadata when is_map(metadata) ->
        one_line(
          Map.get(metadata, @income_account_key) ||
            Map.get(metadata, :quickbooks_income_account)
        )

      _ ->
        nil
    end
  end

  defp metadata_income_account(_), do: nil

  defp product_metadata_income_account(container) do
    container
    |> line_items_list()
    |> Enum.find_value(fn item ->
      price = session_value(item, :price)
      product = session_value(price, :product)
      metadata_income_account(product)
    end)
  end

  defp product_income_account(container) do
    container
    |> line_items_list()
    |> Enum.find_value(&line_item_account_name/1)
  end

  defp line_items_list(container) when is_map(container) do
    case session_value(container, :line_items) do
      %{data: items} when is_list(items) -> items
      %{"data" => items} when is_list(items) -> items
      items when is_list(items) -> items
      _ -> []
    end
  end

  defp line_items_list(_), do: []

  defp line_item_account_name(item) when is_map(item) do
    price = session_value(item, :price)
    product = session_value(price, :product)

    metadata_income_account(product) ||
      one_line(session_value(product, :name)) ||
      one_line(session_value(item, :description))
  end

  defp line_item_account_name(_), do: nil

  defp known_link_account(link) do
    case session_value(link, :url) do
      url when is_binary(url) ->
        known = known_link(url)
        known && known.account

      _ ->
        nil
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
  # entry or an unexpanded PaymentLink in tests still posts to that fund.
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
    key = payment_link_cache_key(id)

    case Cachex.get(:ysc_cache, key) do
      {:ok, link} when is_map(link) ->
        {:ok, link}

      _ ->
        case fetch_payment_link(id) do
          {:ok, link} = ok ->
            Cachex.put(:ysc_cache, key, link, expire: @payment_link_cache_ttl)
            ok

          other ->
            other
        end
    end
  end

  defp fetch_payment_link(id) do
    client = stripe_client()

    # function_exported?/3 is false until the module is loaded. A missing
    # callback must not fail the webhook: unrelated Checkout Sessions would
    # otherwise retry until the event is dead.
    cond do
      Code.ensure_loaded?(client) and
          function_exported?(client, :retrieve_payment_link, 2) ->
        client.retrieve_payment_link(id, @payment_link_expand)

      Code.ensure_loaded?(client) and
          function_exported?(client, :retrieve_payment_link, 1) ->
        client.retrieve_payment_link(id)

      true ->
        {:error, :retrieve_payment_link_not_implemented}
    end
  end

  defp warm_paid_session(session) do
    if session_value(session, :payment_status) == "paid" do
      case payment_link_id(session) do
        id when is_binary(id) ->
          warm_donation_link(session, id)

        _ ->
          :ok
      end
    else
      :ok
    end
  end

  defp warm_donation_link(session, payment_link_id) do
    case retrieve_payment_link(payment_link_id) do
      {:ok, link} ->
        case resolve_donation_link(session, link) do
          nil ->
            :ok

          _resolved_link ->
            warm_fee(session)
        end

      {:error, _reason} ->
        :ok
    end
  end

  defp warm_fee(session) do
    payment_intent_id =
      WebhookHandler.extract_id_from_expandable(
        session_value(session, :payment_intent)
      )

    cond do
      not is_binary(payment_intent_id) ->
        :ok

      match?(%Payment{}, Ledgers.get_payment_by_external_id(payment_intent_id)) ->
        :ok

      true ->
        cached_stripe_fee(payment_intent_id)
        :ok
    end
  end

  defp payment_link_cache_key(id), do: "stripe_donation_payment_link:#{id}"
  defp fee_cache_key(id), do: "stripe_donation_fee:#{id}"

  defp data_object(%{object: object}), do: object
  defp data_object(%{"object" => object}), do: object
  defp data_object(_), do: nil

  defp raw_configured_links do
    config = Application.get_env(:ysc, :stripe_donation_payment_links, [])

    if is_list(config) do
      Keyword.get(config, :links, []) ++ Keyword.get(config, :urls, [])
    else
      []
    end
  end

  defp account_for_link(link) do
    url = link_value(link, :url)
    known = if is_binary(url), do: known_link(url), else: nil
    present_string(link_value(link, :account)) || (known && known.account)
  end

  defp link_value(%{url: url}, :url), do: url
  defp link_value(url, :url) when is_binary(url), do: url
  defp link_value(link, :url) when is_map(link), do: Map.get(link, "url")

  defp link_value(link, key) when is_map(link) and is_atom(key) do
    Map.get(link, key) || Map.get(link, Atom.to_string(key))
  end

  defp link_value(_, _), do: nil

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
