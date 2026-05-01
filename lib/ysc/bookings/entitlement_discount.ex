defmodule Ysc.Bookings.EntitlementDiscount do
  @moduledoc false

  # Product rules (member booking entitlements):
  # - At most one entitlement applies per booking; pick the one with the largest discount.
  # - Free nights discount the first N nights proportionally: (N / total_nights) * subtotal,
  #   then scale by guest cap: min(headcount, max_guests) / headcount when max_guests is set
  #   (e.g. "2 adults" benefit on a 4-adult booking discounts half the proportional night credit).
  # - For buyout with percent or free nights, discount is capped by buyout_max_discount (Option A).
  # - Room-specific entitlements only apply to :room mode and require that room in the selection.
  # - Headcount = adults + children. max_guests limits how many guests the benefit covers, not eligibility.
  # - No stacking of multiple entitlement rows on a single booking.

  alias Ysc.Bookings.BookingEntitlement

  @spec eligible?(
          BookingEntitlement.t(),
          atom(),
          atom(),
          [binary()],
          non_neg_integer()
        ) :: boolean()
  def eligible?(
        %BookingEntitlement{} = ent,
        property,
        booking_mode,
        room_ids,
        _headcount
      ) do
    cond do
      ent.status != :active ->
        false

      expired_for_checkout?(ent) ->
        false

      ent.property && ent.property != property ->
        false

      ent.max_guests && is_integer(ent.max_guests) && ent.max_guests < 1 ->
        false

      ent.room_id && booking_mode != :room ->
        false

      ent.room_id && booking_mode == :room && ent.room_id not in room_ids ->
        false

      booking_mode == :buyout && !buyout_allowed?(ent) ->
        false

      true ->
        true
    end
  end

  @doc false
  def expired_for_checkout?(%BookingEntitlement{expires_at: nil}), do: false

  def expired_for_checkout?(%BookingEntitlement{expires_at: exp}) do
    DateTime.compare(exp, DateTime.utc_now()) != :gt
  end

  defp buyout_allowed?(%BookingEntitlement{benefit_kind: :fixed_amount_off}),
    do: true

  defp buyout_allowed?(%BookingEntitlement{
         benefit_kind: k,
         buyout_max_discount: cap
       })
       when k in [:percent_off, :free_nights] do
    cap != nil && Money.positive?(cap)
  end

  defp buyout_allowed?(_), do: false

  @spec discount_for(
          BookingEntitlement.t(),
          atom(),
          Money.t() | nil,
          pos_integer(),
          pos_integer()
        ) :: Money.t()
  def discount_for(
        %BookingEntitlement{} = ent,
        booking_mode,
        nil,
        nights,
        headcount
      )
      when nights > 0 do
    discount_for(ent, booking_mode, Money.new(0, :USD), nights, headcount)
  end

  def discount_for(
        %BookingEntitlement{} = ent,
        booking_mode,
        subtotal,
        nights,
        headcount
      )
      when nights > 0 do
    case ent.benefit_kind do
      :fixed_amount_off ->
        subtotal
        |> fixed_discount(ent.amount_off)
        |> scale_discount_by_guest_cap(ent, headcount)

      :percent_off ->
        raw =
          case Money.mult(subtotal, Decimal.div(ent.percent_off, 100)) do
            {:ok, m} -> m
            _ -> Money.new(0, :USD)
          end

        raw = scale_discount_by_guest_cap(raw, ent, headcount)

        if booking_mode == :buyout do
          cap_discount(raw, ent.buyout_max_discount)
        else
          raw
        end

      :free_nights ->
        n = min(ent.free_nights, nights)

        night_ratio = Decimal.div(Decimal.new(n), Decimal.new(nights))
        guest_ratio = guest_coverage_ratio(ent, headcount)
        combined = Decimal.mult(night_ratio, guest_ratio)

        raw =
          case Money.mult(subtotal, combined) do
            {:ok, m} -> m
            _ -> Money.new(0, :USD)
          end

        if booking_mode == :buyout do
          cap_discount(raw, ent.buyout_max_discount)
        else
          raw
        end
    end
    |> ensure_at_most(subtotal)
  end

  def discount_for(_ent, _mode, _subtotal, nights, _) when nights <= 0 do
    Money.new(0, :USD)
  end

  defp cap_discount(m, cap) when not is_nil(cap) do
    # Money.cmp/2 returns -1 | 0 | 1 (or {:error, _} on currency mismatch).
    case Money.cmp(m, cap) do
      1 -> cap
      _ -> m
    end
  end

  defp cap_discount(m, _), do: m

  defp guest_coverage_ratio(_ent, headcount) when headcount <= 0,
    do: Decimal.new(0)

  defp guest_coverage_ratio(%BookingEntitlement{max_guests: nil}, _headcount),
    do: Decimal.new(1)

  defp guest_coverage_ratio(%BookingEntitlement{max_guests: cap}, headcount)
       when is_integer(cap) and cap > 0 do
    Decimal.div(Decimal.new(min(headcount, cap)), Decimal.new(headcount))
  end

  defp guest_coverage_ratio(%BookingEntitlement{max_guests: _}, _headcount),
    do: Decimal.new(0)

  defp scale_discount_by_guest_cap(%Money{} = discount, ent, headcount) do
    g = guest_coverage_ratio(ent, headcount)

    case Decimal.compare(g, Decimal.new(1)) do
      :eq ->
        discount

      _ ->
        case Money.mult(discount, g) do
          {:ok, m} -> m
          _ -> Money.new(0, :USD)
        end
    end
  end

  defp fixed_discount(subtotal, amount_off) when not is_nil(amount_off) do
    ensure_at_most(amount_off, subtotal)
  end

  defp fixed_discount(_, _), do: Money.new(0, :USD)

  defp ensure_at_most(%Money{} = discount, %Money{} = subtotal) do
    case Money.cmp(discount, subtotal) do
      1 -> subtotal
      _ -> discount
    end
  end

  @doc """
  Picks the single active entitlement that yields the maximum discount, if any.
  """
  @spec pick_best(
          [BookingEntitlement.t()],
          atom(),
          atom(),
          [binary()],
          non_neg_integer(),
          Money.t() | nil,
          pos_integer()
        ) :: {BookingEntitlement.t() | nil, Money.t(), Money.t() | nil}
  def pick_best(
        entitlements,
        property,
        booking_mode,
        room_ids,
        headcount,
        subtotal,
        nights
      ) do
    total_base = subtotal || Money.new(0, :USD)

    entitlements
    |> Enum.filter(&eligible?(&1, property, booking_mode, room_ids, headcount))
    |> Enum.map(fn ent ->
      d = discount_for(ent, booking_mode, total_base, nights, headcount)
      {ent, d}
    end)
    |> reduce_best_pair()
    |> case do
      nil ->
        {nil, Money.new(0, :USD), subtotal}

      {ent, discount} ->
        case Money.sub(total_base, discount) do
          {:ok, total} -> {ent, discount, total}
          _ -> {ent, discount, Money.new(0, :USD)}
        end
    end
  end

  defp reduce_best_pair([]), do: nil

  defp reduce_best_pair([first | rest]) do
    Enum.reduce(rest, first, fn {_, d} = pair, {_, d0} = acc ->
      case Money.cmp(d, d0) do
        1 -> pair
        0 -> acc
        -1 -> acc
        _ -> acc
      end
    end)
  end
end
