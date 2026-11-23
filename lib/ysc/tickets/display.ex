defmodule Ysc.Tickets.Display do
  @moduledoc """
  Formats ticket tier names and quantity summaries for UI and ledger copy.

  Centralizes the "2x VIP, 1x General Admission" pattern used in payment
  history, ledger descriptions, and similar summaries.
  """

  alias Ysc.Events.TicketTierHelpers

  @default_tier_name "General Admission"

  @doc """
  Returns a tier display name, defaulting missing names to #{@default_tier_name}.
  """
  def tier_name(nil), do: @default_tier_name
  def tier_name(name) when is_binary(name), do: name

  @doc """
  Groups tickets by tier name, sorted by quantity (largest groups first).

  Returns a list of `{tier_name, tickets}` tuples for rendering tier badges
  in home and event detail views.
  """
  def group_tickets_by_tier(tickets) when is_list(tickets) do
    tickets
    |> Enum.group_by(&tier_name_from_ticket/1)
    |> Enum.map(fn {name, tier_tickets} -> {tier_name(name), tier_tickets} end)
    |> Enum.sort_by(
      fn {_tier_name, tier_tickets} -> length(tier_tickets) end,
      :desc
    )
  end

  @doc """
  Groups tickets by tier and returns a comma-separated quantity summary.

  ## Options

    * `:exclude_cancelled` - when true, omits tickets with status `:cancelled`
  """
  def format_tier_quantities(tickets, opts \\ []) when is_list(tickets) do
    tickets
    |> tickets_for_summary(opts)
    |> Enum.group_by(&tier_name_from_ticket/1)
    |> Enum.sort_by(fn {tier_name, _tier_tickets} -> tier_name(tier_name) end)
    |> Enum.map_join(", ", fn {tier_name, tier_tickets} ->
      "#{length(tier_tickets)}x #{tier_name(tier_name)}"
    end)
  end

  @doc """
  Payment-history summary for a ticket order's tickets.

  Returns `"No ticket details"` when tickets are nil, `"All tickets refunded"`
  when every ticket is cancelled, and appends `(N refunded)` when applicable.
  """
  def format_order_ticket_summary(nil), do: "No ticket details"

  def format_order_ticket_summary(tickets) when is_list(tickets) do
    refunded_count = Enum.count(tickets, &cancelled?/1)
    active_tickets = Enum.reject(tickets, &cancelled?/1)

    ticket_summary =
      if active_tickets == [] do
        "All tickets refunded"
      else
        format_tier_quantities(active_tickets)
      end

    if refunded_count > 0 do
      "#{ticket_summary} (#{refunded_count} refunded)"
    else
      ticket_summary
    end
  end

  @doc """
  Ledger description for complimentary ticket orders.
  """
  def format_ledger_order_description(ticket_order) do
    event_title =
      if ticket_order.event, do: ticket_order.event.title, else: "Event"

    case ticket_order.tickets do
      tickets when is_list(tickets) and tickets != [] ->
        ticket_summary = format_tier_quantities(tickets)
        "Free Tickets: #{event_title} (#{ticket_summary})"

      _ ->
        "Free Tickets: #{event_title}"
    end
  end

  defp tickets_for_summary(tickets, opts) do
    if Keyword.get(opts, :exclude_cancelled, false) do
      Enum.reject(tickets, &cancelled?/1)
    else
      tickets
    end
  end

  defp tier_name_from_ticket(%{ticket_tier: %{name: name}}), do: name
  defp tier_name_from_ticket(%{ticket_tier: nil}), do: nil

  defp tier_name_from_ticket(%{ticket_tier: %Ecto.Association.NotLoaded{}}),
    do: nil

  defp tier_name_from_ticket(_), do: nil

  defp cancelled?(%{status: :cancelled}), do: true
  defp cancelled?(_), do: false

  @doc """
  Short count of event tickets vs donations for the Your Tickets list.

  Donations are not event tickets, so a donation-only order says
  `"1 Donation"` rather than `"1 Ticket"`.
  """
  def order_item_count_label(tickets) when is_list(tickets) do
    donation_count = Enum.count(tickets, &TicketTierHelpers.donation_ticket?/1)
    ticket_count = length(tickets) - donation_count

    cond do
      ticket_count > 0 and donation_count > 0 ->
        "#{count_noun(ticket_count, "Ticket")} · #{count_noun(donation_count, "Donation")}"

      donation_count > 0 ->
        count_noun(donation_count, "Donation")

      true ->
        count_noun(ticket_count, "Ticket")
    end
  end

  defp count_noun(1, word), do: "1 #{word}"
  defp count_noun(count, word), do: "#{count} #{word}s"

  @doc """
  How many event tickets can still be bought, for the public event sidebar.

  Uses "tickets" (not "spots") so it matches Get Tickets and the quantity
  picker. Singular: `"1 ticket left"`.
  """
  def tickets_left_label(1), do: "1 ticket left"

  def tickets_left_label(count) when is_integer(count) and count > 1,
    do: "#{count} tickets left"

  @doc """
  Urgency line when demand is high and remaining count is 10 or fewer.

  States the actual remaining count (`"Only 5 tickets left"`), not
  `"Less than 5"` which would mean fewer than remain.
  """
  def tickets_left_demand_label(count)
      when is_integer(count) and count > 0 do
    "Only #{tickets_left_label(count)}"
  end

  # Fill thresholds for the event sidebar's demand indicator. Below `filling`
  # a progress bar says almost nothing, so it stays hidden.
  @demand_filling_percent 50
  @demand_scarce_percent 85

  @doc """
  Decides what the event sidebar's demand indicator may claim.

  "Demand" (recent sales velocity, `selling_fast?`) and "scarcity" (how full
  the event is) are separate signals, and each visual element is shown only
  once its own signal is true:

    * `:momentum` — selling fast, but under #{@demand_filling_percent}% full or
      capacity unknown. A compact line, no bar.
    * `:filling` — selling fast and #{@demand_filling_percent}%+ full. Adds
      the fill bar.
    * `:scarce` — #{@demand_scarce_percent}%+ full. Strongest treatment; the
      remaining count is stated. Reads "Demand is high" when also selling fast,
      otherwise "Almost full".

  Returns `nil` when there is nothing honest to say. `sold_percentage` is an
  integer or `nil` (no capacity cap); `available_capacity` is an integer or
  `:unlimited`.
  """
  def demand_indicator(selling_fast?, sold_percentage, available_capacity) do
    cond do
      is_integer(sold_percentage) and sold_percentage >= @demand_scarce_percent ->
        %{
          level: :scarce,
          headline:
            if(selling_fast?, do: "Demand is high", else: "Almost full"),
          detail: remaining_detail(available_capacity),
          show_bar?: true
        }

      selling_fast? and is_integer(sold_percentage) and
          sold_percentage >= @demand_filling_percent ->
        %{
          level: :filling,
          headline: "Demand is high",
          detail: "Filling up",
          show_bar?: true
        }

      selling_fast? ->
        %{
          level: :momentum,
          headline: "Demand is high",
          detail: momentum_detail(available_capacity),
          show_bar?: false
        }

      true ->
        nil
    end
  end

  @doc """
  Percent of capacity taken, capped at 100, or `nil` when there is no cap or
  the count is unknown. Shared by event cards, which only have a confirmed
  ticket count; the event page adds held tickets on top of it.
  """
  def sold_percentage(max_attendees, committed)
      when is_integer(max_attendees) and max_attendees > 0 and
             is_integer(committed) do
    min(round(committed / max_attendees * 100), 100)
  end

  def sold_percentage(_max_attendees, _committed), do: nil

  defp remaining_detail(count) when is_integer(count) and count > 10,
    do: tickets_left_label(count)

  defp remaining_detail(count) when is_integer(count) and count > 0,
    do: tickets_left_demand_label(count)

  defp remaining_detail(_count), do: nil

  defp momentum_detail(count) when is_integer(count) and count in 1..10,
    do: tickets_left_demand_label(count)

  defp momentum_detail(_count), do: "Tickets are selling quickly"

  @doc """
  True when the order total is $0 (free RSVP, $0 tiers, or fully discounted).
  """
  def complimentary_order?(%{total_amount: %Money{} = total}),
    do: Money.zero?(total)

  def complimentary_order?(_), do: false

  @doc """
  Member-facing label for an individual ticket's status.
  """
  def ticket_status_label(:confirmed), do: "Ready to use"
  def ticket_status_label(:pending), do: "Awaiting payment"
  def ticket_status_label(:cancelled), do: "Cancelled"
  def ticket_status_label(:expired), do: "Expired"

  def ticket_status_label(status),
    do: status |> to_string() |> String.capitalize()

  @doc """
  Member-facing label for a ticket order's status.

  Pass `complimentary: true` for free / $0 holds so the badge does not
  ask for payment.
  """
  def order_status_label(status, opts \\ [])

  def order_status_label(:pending, opts) when is_list(opts) do
    if complimentary_opt?(opts), do: "Confirm tickets", else: "Payment needed"
  end

  def order_status_label(:completed, opts) when is_list(opts) do
    if complimentary_opt?(opts), do: "Confirmed", else: "Paid"
  end

  def order_status_label(:expired, _opts), do: "Checkout expired"
  def order_status_label(:cancelled, _opts), do: "Cancelled"

  def order_status_label(status, _opts),
    do: status |> to_string() |> String.capitalize()

  defp complimentary_opt?(opts), do: Keyword.get(opts, :complimentary, false)
end
