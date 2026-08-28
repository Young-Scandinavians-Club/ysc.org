defmodule YscWeb.BookingDisplay do
  @moduledoc """
  Human-readable booking labels for member views, emails, and admin lists.

  Status helpers cover booking/payment badges. Count helpers (`nights_label/1`,
  `guests_label/3`, `adults_label/1`) are the shared pluralization used in
  booking emails and LiveViews. Clock labels (`checkin_time_label/0`,
  `checkout_time_label/0`) format `Ysc.Bookings.checkin_time/0` and
  `checkout_time/0` for member-facing copy.
  """

  alias Ysc.Bookings

  @doc """
  Badge `type` for booking status on member booking detail pages.
  """
  def status_badge_type(:complete), do: "green"
  def status_badge_type(:hold), do: "yellow"
  def status_badge_type(:canceled), do: "red"
  def status_badge_type(:refunded), do: "red"
  def status_badge_type(_), do: "gray"

  @doc """
  Member-friendly label for a booking status atom.
  """
  def status_label(:hold), do: "Awaiting payment"
  def status_label(:complete), do: "Confirmed"
  def status_label(:canceled), do: "Cancelled"
  def status_label(:refunded), do: "Refunded"

  def status_label(status),
    do: status |> to_string() |> String.capitalize()

  @doc """
  Badge `type` for ledger payment status on member booking detail pages.
  """
  def payment_status_badge_type(:completed), do: "green"
  def payment_status_badge_type(:pending), do: "yellow"
  def payment_status_badge_type(:refunded), do: "red"
  def payment_status_badge_type(_), do: "gray"

  @doc """
  Member-friendly label for a ledger payment status atom.
  """
  def payment_status_label(:completed), do: "Completed"
  def payment_status_label(:pending), do: "Pending"
  def payment_status_label(:refunded), do: "Refunded"

  def payment_status_label(status),
    do: status |> to_string() |> String.capitalize()

  @doc """
  Formats a count with a singular/plural unit (`"1 night"`, `"3 adults"`).

  `nil` and non-numeric values are treated as `0`.
  """
  def count_label(count, singular, plural)
      when is_binary(singular) and is_binary(plural) do
    n = to_count(count)
    "#{n} #{if n == 1, do: singular, else: plural}"
  end

  @doc """
  Formats a stay length (`"1 night"`, `"4 nights"`).

  Pass `capitalize: true` for badge copy (`"1 Night"` / `"2 Nights"`).
  """
  def nights_label(nights, opts \\ []) do
    n = to_count(nights)
    unit = if n == 1, do: "night", else: "nights"

    unit =
      if Keyword.get(opts, :capitalize, false),
        do: String.capitalize(unit),
        else: unit

    "#{n} #{unit}"
  end

  @doc """
  Formats an adult count (`"1 adult"`, `"2 adults"`).
  """
  def adults_label(count), do: count_label(count, "adult", "adults")

  @doc """
  Formats a child count (`"1 child"`, `"2 children"`).
  """
  def children_label(count), do: count_label(count, "child", "children")

  @doc """
  Formats a combined guest headcount (`"1 guest"`, `"3 guests"`).
  """
  def people_label(count), do: count_label(count, "guest", "guests")

  @doc """
  Label for a price-breakdown season name.

  Missing names must not show developer fallbacks like "Unnamed season".
  """
  def season_rate_label(name) when is_binary(name) do
    case String.trim(name) do
      "" -> "Season rate"
      trimmed -> trimmed
    end
  end

  def season_rate_label(_), do: "Season rate"

  @doc """
  Formats adult and child counts for booking UIs and emails.

  ## Options

    * `:separator` — between the adult and child parts. Default `", "`.
      Use `" • "` for compact booking summaries.
    * `:omit_zero_adults` — when `true` and adults is 0, omit the adults
      part so a children-only stay renders as `"1 child"`. Default `false`.
    * `:include_total` — when `true`, appends ` (Total: N guest(s))`.
      Default `false`.

  ## Examples

      iex> guests_label(2, 1)
      "2 adults, 1 child"

      iex> guests_label(2, 1, separator: " • ")
      "2 adults • 1 child"

      iex> guests_label(0, 1, omit_zero_adults: true)
      "1 child"

      iex> guests_label(1, 0, include_total: true)
      "1 adult (Total: 1 guest)"
  """
  def guests_label(adults, children, opts \\ []) do
    adults = to_count(adults)
    children = to_count(children)
    separator = Keyword.get(opts, :separator, ", ")
    omit_zero_adults? = Keyword.get(opts, :omit_zero_adults, false)
    include_total? = Keyword.get(opts, :include_total, false)

    parts =
      []
      |> maybe_append_adults(adults, omit_zero_adults?)
      |> maybe_append_children(children)

    summary =
      case parts do
        [] -> adults_label(0)
        _ -> Enum.join(parts, separator)
      end

    if include_total? do
      "#{summary} (#{guests_total_label(adults, children)})"
    else
      summary
    end
  end

  @doc """
  Formats combined headcount as `"Total: 3 guests"`.

  Use next to `guests_label/3` when the total needs separate styling.
  """
  def guests_total_label(adults, children) do
    "Total: #{people_label(to_count(adults) + to_count(children))}"
  end

  @doc """
  12-hour clock label for cabin check-in (e.g. `"3:00 PM"`).

  Derived from `Ysc.Bookings.checkin_time/0` so display copy stays in sync
  with eligibility cutoffs.
  """
  def checkin_time_label, do: format_clock(Bookings.checkin_time())

  @doc """
  12-hour clock label for cabin check-out (e.g. `"11:00 AM"`).

  Derived from `Ysc.Bookings.checkout_time/0`.
  """
  def checkout_time_label, do: format_clock(Bookings.checkout_time())

  defp maybe_append_adults(parts, adults, true) when adults <= 0, do: parts

  defp maybe_append_adults(parts, adults, _),
    do: parts ++ [adults_label(adults)]

  defp maybe_append_children(parts, children) when children > 0,
    do: parts ++ [children_label(children)]

  defp maybe_append_children(parts, _children), do: parts

  defp format_clock(%Time{} = time), do: Calendar.strftime(time, "%-I:%M %p")

  defp to_count(nil), do: 0
  defp to_count(n) when is_integer(n) and n >= 0, do: n
  defp to_count(n) when is_integer(n), do: 0

  defp to_count(n) when is_binary(n) do
    case Integer.parse(n) do
      {parsed, _} when parsed >= 0 -> parsed
      _ -> 0
    end
  end

  defp to_count(_), do: 0
end
