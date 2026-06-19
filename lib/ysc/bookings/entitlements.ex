defmodule Ysc.Bookings.Entitlements do
  @moduledoc """
  CRUD and application logic for member cabin booking entitlements.
  """
  import Ecto.Query, warn: false

  import Ecto.Changeset, only: [put_change: 3]

  alias Ysc.Repo
  alias Ysc.Bookings.{Booking, BookingEntitlement, EntitlementDiscount}
  alias YscWeb.Emails.BookingEntitlementGranted
  alias YscWeb.Emails.Notifier

  ## Queries

  def get_entitlement!(id), do: Repo.get!(BookingEntitlement, id)

  def get_entitlement(nil), do: nil
  def get_entitlement(id), do: Repo.get(BookingEntitlement, id)

  @doc """
  Entitlement ids already attached to another member's active `:hold` booking.

  Optional `exclude_booking_id` ignores the current booking (checkout re-price).
  """
  def entitlement_ids_reserved_on_active_holds(exclude_booking_id \\ nil) do
    query =
      from(b in Booking,
        where: b.status == :hold,
        where: not is_nil(b.applied_booking_entitlement_id),
        select: b.applied_booking_entitlement_id,
        distinct: true
      )

    query =
      if exclude_booking_id do
        where(query, [b], b.id != ^exclude_booking_id)
      else
        query
      end

    Repo.all(query)
  end

  def entitlement_reserved_on_active_hold?(
        entitlement_id,
        exclude_booking_id \\ nil
      )

  def entitlement_reserved_on_active_hold?(entitlement_id, exclude_booking_id)
      when is_binary(entitlement_id) do
    entitlement_id in entitlement_ids_reserved_on_active_holds(
      exclude_booking_id
    )
  end

  def entitlement_reserved_on_active_hold?(
        _entitlement_id,
        _exclude_booking_id
      ), do: false

  @doc """
  Active entitlements for a user: `status` is `:active` and not past `expires_at`
  (end-of-day semantics are unchanged; rows past end date should also be moved to
  `:expired` by `expire_passed_entitlements/1` / the cron worker).
  """
  def list_active_for_user(user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(e in BookingEntitlement,
      where: e.user_id == ^user_id,
      where: e.status == :active,
      where: is_nil(e.expires_at) or e.expires_at > ^now,
      order_by: [asc: e.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Outstanding entitlements: active, not consumed, not expired.
  """
  def list_outstanding(opts \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    property = Keyword.get(opts, :property)
    benefit = Keyword.get(opts, :benefit_kind)

    q =
      from(e in BookingEntitlement,
        join: u in assoc(e, :user),
        left_join: iu in assoc(e, :issued_by_user),
        where: e.status == :active,
        where: is_nil(e.consumed_at),
        where: is_nil(e.consumed_booking_id),
        where: is_nil(e.expires_at) or e.expires_at > ^now,
        order_by: [asc: e.expires_at, asc: e.inserted_at],
        preload: [user: u, issued_by_user: iu]
      )

    q =
      if property do
        where(q, [e], is_nil(e.property) or e.property == ^property)
      else
        q
      end

    q =
      if benefit do
        where(q, [e], e.benefit_kind == ^benefit)
      else
        q
      end

    Repo.all(q)
  end

  @doc """
  Usable cabin entitlements for a member: `status` is `:active`, not consumed,
  and not past `expires_at`.

  These are the rows that apply at checkout and are shown on the member payments page.

  `issued_by_user` is not preloaded (the payments UI does not need it); call
  `Repo.preload/2` when you need that association.
  """
  def list_usable_for_user(user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(e in BookingEntitlement,
      where: e.user_id == ^user_id,
      where: e.status == :active,
      where: is_nil(e.consumed_at),
      where: is_nil(e.consumed_booking_id),
      where: is_nil(e.expires_at) or e.expires_at > ^now,
      order_by: [asc: e.expires_at, asc: e.inserted_at]
    )
    |> Repo.all()
  end

  def list_all_for_user(user_id) do
    from(e in BookingEntitlement,
      where: e.user_id == ^user_id,
      order_by: [desc: e.inserted_at],
      preload: [:issued_by_user, :consumed_booking]
    )
    |> Repo.all()
  end

  @doc """
  Suggested buyout discount cap for Option A: percent_off or free_nights reference
  uses one-night buyout subtotal × (percent/100) or proportional free nights on that night.
  """
  def suggest_buyout_max_discount(
        property,
        checkin_date,
        checkout_date,
        benefit_kind,
        opts \\ []
      ) do
    percent_off = Keyword.get(opts, :percent_off)
    _free_nights = Keyword.get(opts, :free_nights) || 1
    guests_count = Keyword.get(opts, :guests_count, 2)

    case Ysc.Bookings.calculate_booking_price(
           property,
           checkin_date,
           checkout_date,
           :buyout,
           guests_count: guests_count,
           children_count: 0
         ) do
      {:ok, one_night_buyout, _} ->
        case benefit_kind do
          :percent_off when not is_nil(percent_off) ->
            case Money.mult(one_night_buyout, Decimal.div(percent_off, 100)) do
              {:ok, m} -> {:ok, m}
            end

          :free_nights ->
            # Reference: value of one buyout night × number of free nights (caller passes via opts)
            n = max(1, Keyword.get(opts, :free_nights) || 1)

            case Money.mult(one_night_buyout, Decimal.new(n)) do
              {:ok, m} -> {:ok, m}
            end

          _ ->
            {:ok, Money.new(0, :USD)}
        end

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Applies the best eligible entitlement to a computed subtotal and enriches pricing_items.
  Returns `{final_total, pricing_items, subtotal, discount, entitlement_id}`.
  """
  def apply_best_entitlement(
        user_id,
        property,
        booking_mode,
        checkin_date,
        checkout_date,
        subtotal,
        pricing_items,
        opts \\ []
      ) do
    nights = Date.diff(checkout_date, checkin_date)
    guests = Keyword.get(opts, :guests_count, 1)
    children = Keyword.get(opts, :children_count, 0)
    room_ids = Keyword.get(opts, :room_ids, [])
    headcount = guests + children

    reserved_entitlement_ids =
      entitlement_ids_reserved_on_active_holds()
      |> MapSet.new()

    entitlements =
      user_id
      |> list_active_for_user()
      |> Enum.reject(&MapSet.member?(reserved_entitlement_ids, &1.id))

    {ent, discount, final_total} =
      EntitlementDiscount.pick_best(
        entitlements,
        property,
        booking_mode,
        room_ids,
        headcount,
        subtotal,
        nights
      )

    items =
      merge_discount_into_pricing_items(
        pricing_items,
        subtotal,
        discount,
        ent
      )

    ent_id = if ent, do: ent.id, else: nil
    {final_total, items, subtotal, discount, ent_id}
  end

  defp merge_discount_into_pricing_items(items, subtotal, discount, ent) do
    base = items || %{}

    disc_entry =
      if ent && Money.positive?(discount) do
        [
          %{
            "entitlement_id" => to_string(ent.id),
            "summary" => entitlement_summary(ent),
            "amount" => money_to_map(discount)
          }
        ]
      else
        []
      end

    base
    |> Map.put("subtotal", money_to_map(money_or_zero(subtotal)))
    |> Map.put("discount_total", money_to_map(money_or_zero(discount)))
    |> Map.put("discounts", disc_entry)
  end

  defp money_or_zero(nil), do: Money.new(0, :USD)
  defp money_or_zero(%Money{} = m), do: m

  defp money_to_map(%Money{} = m) do
    %{
      "amount" => Decimal.to_string(m.amount),
      "currency" => to_string(m.currency)
    }
  end

  defp entitlement_summary(%BookingEntitlement{benefit_kind: :free_nights} = e) do
    n = e.free_nights || 0
    "#{n} free night#{if n == 1, do: "", else: "s"}"
  end

  defp entitlement_summary(%BookingEntitlement{benefit_kind: :percent_off} = e) do
    "#{Decimal.round(e.percent_off || 0, 2)}% off stay"
  end

  defp entitlement_summary(
         %BookingEntitlement{benefit_kind: :fixed_amount_off} = e
       ) do
    "#{Ysc.MoneyHelper.format_money!(e.amount_off)} off stay"
  end

  @doc """
  Recomputes gross from current rates, then applies discount for the locked entitlement id.
  """
  def price_with_locked_entitlement(booking, subtotal, booking_mode, opts \\ []) do
    guests = Keyword.get(opts, :guests_count, booking.guests_count)
    children = Keyword.get(opts, :children_count, booking.children_count || 0)
    room_ids = Keyword.get(opts, :room_ids, [])
    headcount = guests + children
    nights = Date.diff(booking.checkout_date, booking.checkin_date)

    case get_entitlement(booking.applied_booking_entitlement_id) do
      nil ->
        {:ok,
         %{
           subtotal: subtotal,
           discount: Money.new(0, :USD),
           total: subtotal,
           breakdown_additions: %{}
         }}

      ent ->
        cond do
          ent.status != :active ||
              EntitlementDiscount.expired_for_checkout?(ent) ->
            {:error, :entitlement_no_longer_valid}

          entitlement_reserved_on_active_hold?(ent.id, booking.id) ->
            {:error, :entitlement_no_longer_valid}

          not EntitlementDiscount.eligible?(
            ent,
            booking.property,
            booking_mode,
            room_ids,
            headcount
          ) ->
            {:error, :entitlement_not_eligible_for_booking}

          true ->
            total_base = subtotal || Money.new(0, :USD)

            discount =
              EntitlementDiscount.discount_for(
                ent,
                booking_mode,
                total_base,
                nights,
                headcount
              )

            case Money.sub(total_base, discount) do
              {:ok, total} ->
                {:ok,
                 %{
                   subtotal: subtotal,
                   discount: discount,
                   total: total,
                   breakdown_additions: %{
                     entitlement_id: ent.id,
                     entitlement_summary: entitlement_summary(ent)
                   }
                 }}

              {:error, _} ->
                {:error, :discount_calculation_failed}
            end
        end
    end
  end

  @doc """
  Default string-keyed params for the admin entitlement grant form (`as: :entitlement`).
  """
  def entitlement_grant_default_params do
    %{
      "benefit_kind" => "percent_off",
      "property" => "",
      "max_guests" => "",
      "free_nights" => "1",
      "percent_off" => "50",
      "amount_off" => "",
      "buyout_max_discount" => "250",
      "expires_on" => "",
      "internal_note" => ""
    }
  end

  @doc """
  Builds attrs for `create_entitlement/2` from admin form params nested under `"entitlement"`.

  Pass `member_user_id` when granting from a known user context; otherwise include
  `"user_id"` in the form params (e.g. autocomplete hidden field).
  """
  def grant_attrs_from_entitlement_form(
        %{} = p,
        issued_by_user_id,
        member_user_id \\ nil
      ) do
    user_id = member_user_id || normalize_user_id(p["user_id"])

    kind =
      case p["benefit_kind"] do
        "free_nights" -> :free_nights
        "fixed_amount_off" -> :fixed_amount_off
        _ -> :percent_off
      end

    property =
      case p["property"] do
        "tahoe" -> :tahoe
        "clear_lake" -> :clear_lake
        _ -> nil
      end

    %{
      user_id: user_id,
      issued_by_user_id: issued_by_user_id,
      benefit_kind: kind,
      property: property,
      max_guests: empty_or_int(p["max_guests"]),
      free_nights: empty_or_int(p["free_nights"]),
      percent_off: empty_or_decimal(p["percent_off"]),
      amount_off: empty_or_money(p["amount_off"]),
      buyout_max_discount: empty_or_money(p["buyout_max_discount"]),
      expires_at: expires_on_to_utc_datetime(p["expires_on"]),
      internal_note: empty_or_string(p["internal_note"])
    }
  end

  defp normalize_user_id(s) when s in [nil, ""], do: nil

  defp normalize_user_id(s) do
    t = s |> to_string() |> String.trim()
    if t == "", do: nil, else: t
  end

  defp empty_or_int(s) when s in [nil, ""], do: nil

  defp empty_or_int(s) do
    case Integer.parse(to_string(s)) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp empty_or_decimal(s) when s in [nil, ""], do: nil

  defp empty_or_decimal(s) do
    case Decimal.parse(to_string(s)) do
      {d, _} -> d
      :error -> nil
    end
  end

  defp empty_or_money(s) when s in [nil, ""], do: nil

  defp empty_or_money(s) do
    t = String.trim(to_string(s))

    case Decimal.parse(t) do
      {d, _} -> Money.new(:USD, d)
      :error -> nil
    end
  end

  defp empty_or_string(s) when s in [nil, ""], do: nil
  defp empty_or_string(s), do: String.trim(to_string(s))

  defp expires_on_to_utc_datetime(s) when s in [nil, ""], do: nil

  defp expires_on_to_utc_datetime(iso_date) do
    tz = Application.get_env(:ysc, :default_timezone, "America/Los_Angeles")

    with {:ok, date} <- Date.from_iso8601(to_string(iso_date)),
         {:ok, local_dt} <- date_end_of_day_local(date, tz) do
      DateTime.shift_zone!(local_dt, "Etc/UTC")
    else
      _ -> nil
    end
  end

  defp date_end_of_day_local(date, tz) do
    case DateTime.new(date, ~T[23:59:59], tz) do
      {:ok, dt} ->
        {:ok, dt}

      {:ambiguous, dt1, dt2} ->
        later =
          if DateTime.compare(dt1, dt2) == :gt do
            dt1
          else
            dt2
          end

        {:ok, later}

      {:gap, _, _} ->
        {:error, :gap}

      {:error, _} = err ->
        err
    end
  end

  def create_entitlement(attrs, opts \\ []) do
    send_mail? = Keyword.get(opts, :send_notification, true)

    user_id = Map.get(attrs, :user_id)
    issued_by_user_id = Map.get(attrs, :issued_by_user_id)
    rest = Map.drop(attrs, [:user_id, :issued_by_user_id])

    changeset =
      %BookingEntitlement{}
      |> BookingEntitlement.create_changeset(rest)
      |> put_change(:user_id, user_id)
      |> put_change(:issued_by_user_id, issued_by_user_id)
      |> Ecto.Changeset.validate_required([:user_id])

    changeset
    |> Repo.insert()
    |> case do
      {:ok, ent} = ok ->
        if send_mail? do
          case schedule_granted_email(ent) do
            nil -> ok
            {:error, _} = err -> err
            _job -> ok
          end
        else
          ok
        end

      other ->
        other
    end
  end

  def revoke_entitlement(%BookingEntitlement{status: :active} = ent) do
    ent
    |> BookingEntitlement.revoke_changeset()
    |> Repo.update()
  end

  def revoke_entitlement(%BookingEntitlement{}), do: {:error, :not_revocable}

  @doc """
  Retires active entitlements whose `expires_at` is set and not after now.

  Sets `status` to `:expired` so they are excluded from checkout and admin
  outstanding lists (same as `:active` filters).

  Indefinite benefits (`expires_at` nil) are never changed here.

  ## Options

  - `:limit` — max rows to process in one run (default `500`).

  Returns `{:ok, %{expired: integer, failed: integer}}`.
  """
  def expire_passed_entitlements(opts \\ []) do
    limit = Keyword.get(opts, :limit, 500)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    candidate_subq =
      from(e in BookingEntitlement,
        where: e.status == :active,
        where: not is_nil(e.expires_at) and e.expires_at <= ^now,
        order_by: [asc: e.expires_at],
        limit: ^limit,
        select: e.id
      )

    {expired_count, _} =
      from(e in BookingEntitlement,
        where: e.id in subquery(candidate_subq),
        where: e.status == :active
      )
      |> Repo.update_all(set: [status: "expired", updated_at: now])

    {:ok, %{expired: expired_count, failed: 0}}
  end

  @doc """
  Locks an active entitlement row for update within the current transaction.

  Call this immediately before `consume_for_booking!/2` so concurrent confirm
  attempts serialize on the entitlement row and cannot double-consume.
  """
  def lock_entitlement_for_consume(nil), do: nil

  def lock_entitlement_for_consume(entitlement_id)
      when is_binary(entitlement_id) do
    from(e in BookingEntitlement,
      where: e.id == ^entitlement_id and e.status == :active,
      lock: "FOR UPDATE"
    )
    |> Repo.one()
  end

  @doc """
  Marks an entitlement consumed when a booking is confirmed. Must run in same DB transaction.
  """
  def consume_for_booking!(entitlement_id, booking_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {n, _} =
      Repo.update_all(
        from(e in BookingEntitlement,
          where: e.id == ^entitlement_id and e.status == :active
        ),
        set: [
          status: :consumed,
          consumed_at: now,
          consumed_booking_id: booking_id,
          updated_at: now
        ]
      )

    if n == 1, do: :ok, else: {:error, :entitlement_consume_failed}
  end

  defp schedule_granted_email(%BookingEntitlement{} = ent) do
    ent = Repo.preload(ent, :user)
    user = ent.user

    if user && user.email do
      variables = BookingEntitlementGranted.prepare_email_data(ent, user)

      Notifier.schedule_email(
        user.email,
        "booking_entitlement_granted:#{ent.id}",
        BookingEntitlementGranted.get_subject(),
        BookingEntitlementGranted.get_template_name(),
        variables,
        BookingEntitlementGranted.plain_text_summary(variables),
        user.id,
        reply_to:
          (ent.property && Ysc.EmailConfig.booking_reply_to(ent.property)) ||
            Ysc.EmailConfig.contact_email()
      )
    end
  end

  @doc false
  def ci_query_explain_query do
    alias Ysc.Ci.QueryExplain.Fixtures

    now = Fixtures.now()

    from(e in BookingEntitlement,
      join: u in assoc(e, :user),
      left_join: iu in assoc(e, :issued_by_user),
      where: e.status == :active,
      where: is_nil(e.consumed_at),
      where: is_nil(e.consumed_booking_id),
      where: is_nil(e.expires_at) or e.expires_at > ^now,
      order_by: [asc: e.expires_at, asc: e.inserted_at],
      preload: [user: u, issued_by_user: iu]
    )
  end
end
