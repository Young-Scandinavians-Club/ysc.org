defmodule Ysc.Tickets.GuestCheckout do
  @moduledoc """
  Ticket orders placed without an account.

  Only tiers sold to the public (`Ysc.Events.TierAudience`) can be bought this
  way, and only tiers that need nothing beyond the buyer's name and email (no
  per-ticket registration or attendee questions). The buyer is identified by
  `guest_email` / `guest_first_name` / `guest_last_name` on the order; tickets
  carry no `user_id`.

  Tickets are reached through signed links (`Ysc.Tickets.AccessToken`, `/t/:token`)
  rather than a login, and the confirmation email goes to the guest's address.
  """
  import Ecto.Query

  alias Ysc.Events.TicketTier
  alias Ysc.Events.TierAudience
  alias Ysc.Events.TierPurchaseLimits
  alias Ysc.Repo
  alias Ysc.Tickets
  alias Ysc.Tickets.BookingLocker
  alias Ysc.Tickets.TicketOrder

  @selection_salt "guest_checkout_selection_v1"
  @selection_max_age_seconds 30 * 60

  @type guest :: %{
          required(:email) => String.t(),
          required(:first_name) => String.t(),
          required(:last_name) => String.t()
        }

  @doc """
  Signs a ticket selection so the picker can hand it to the guest checkout
  page without trusting the URL. Valid for 30 minutes.
  """
  def sign_selection(event_id, ticket_selections)
      when is_map(ticket_selections) do
    Phoenix.Token.sign(
      YscWeb.Endpoint,
      @selection_salt,
      {event_id, ticket_selections}
    )
  end

  @doc "Verifies a token from `sign_selection/2` for `event_id`."
  def verify_selection(token, event_id) when is_binary(token) do
    case Phoenix.Token.verify(YscWeb.Endpoint, @selection_salt, token,
           max_age: @selection_max_age_seconds
         ) do
      {:ok, {^event_id, selections}}
      when is_map(selections) and selections != %{} ->
        {:ok, selections}

      _ ->
        {:error, :invalid}
    end
  end

  def verify_selection(_, _), do: {:error, :invalid}

  @doc """
  Whether `tiers` (selected tier structs) can all be bought without an account.

  Returns `:ok`, or `{:error, :guest_checkout_not_allowed}` when any tier is
  member-only, or needs attendee details we do not collect from guests.
  """
  def validate_tiers(tiers) when is_list(tiers) do
    if tiers != [] and Enum.all?(tiers, &guest_purchasable?/1),
      do: :ok,
      else: {:error, :guest_checkout_not_allowed}
  end

  @doc "True when a single tier can be bought without an account."
  def guest_purchasable?(%TicketTier{} = tier) do
    TierAudience.public?(tier) and tier.requires_registration != true and
      List.wrap(tier.attendee_questions) == []
  end

  def guest_purchasable?(_), do: false

  @doc """
  Creates a pending guest order for `event_id` holding the selected tickets.

  `ticket_selections` is `tier_id => quantity` (donation tiers: amount in
  cents), as for `Ysc.Tickets.create_ticket_order/4`. Returns
  `{:ok, %TicketOrder{}}` (tickets and tiers loaded) or `{:error, reason}`:
  `:invalid_guest` / `{:invalid_guest, %Ecto.Changeset{}}` for bad contact
  details, `:guest_checkout_not_allowed`, `:tier_purchase_limit_exceeded`,
  `:too_many_open_holds`, `:ticket_quantity_exceeds_limit`, and the usual
  booking errors (`:overbooked`, `:event_capacity_exceeded`,
  `:event_in_past`, ...).
  """
  def create_order(guest, event_id, ticket_selections)
      when is_map(ticket_selections) do
    with {:ok, guest} <- validate_guest(guest),
         {:ok, tiers} <- load_tiers(event_id, ticket_selections),
         :ok <- validate_tiers(tiers),
         :ok <- Tickets.validate_checkout_quantities(ticket_selections, tiers) do
      create_locked(guest, event_id, ticket_selections, tiers)
    end
  end

  @doc """
  Validates and normalizes contact details.

  Returns `{:ok, guest}` with a trimmed, lowercased email, or
  `{:error, {:invalid_guest, changeset}}` so the form can show messages.
  """
  def validate_guest(guest) when is_map(guest) do
    attrs = %{
      guest_email: guest[:email] || guest["email"],
      guest_first_name: guest[:first_name] || guest["first_name"],
      guest_last_name: guest[:last_name] || guest["last_name"],
      event_id: "valid",
      total_amount: Money.new(0, :USD),
      expires_at: DateTime.utc_now()
    }

    changeset = TicketOrder.guest_create_changeset(%TicketOrder{}, attrs)

    contact_errors =
      Enum.filter(changeset.errors, fn {field, _} ->
        field in [:guest_email, :guest_first_name, :guest_last_name]
      end)

    if contact_errors == [] do
      {:ok,
       %{
         email: Ecto.Changeset.get_field(changeset, :guest_email),
         first_name: Ecto.Changeset.get_field(changeset, :guest_first_name),
         last_name: Ecto.Changeset.get_field(changeset, :guest_last_name)
       }}
    else
      {:error, {:invalid_guest, %{changeset | errors: contact_errors}}}
    end
  end

  def validate_guest(_), do: {:error, :invalid_guest}

  # Selected tiers of this event, as full structs (so registration/question
  # needs are visible). Unknown ids or tiers of another event fail the order.
  defp load_tiers(event_id, ticket_selections) do
    ids = Map.keys(ticket_selections)

    tiers =
      Repo.all(
        from(tt in TicketTier,
          where: tt.id in ^ids and tt.event_id == ^event_id
        )
      )

    if length(tiers) == length(ids) and ids != [],
      do: {:ok, tiers},
      else: {:error, :tier_validation_failed}
  end

  defp create_locked(guest, event_id, ticket_selections, tiers) do
    result =
      Repo.transaction(fn ->
        lock_guest_event!(guest.email, event_id)

        with :ok <-
               validate_guest_limits(
                 guest.email,
                 event_id,
                 ticket_selections,
                 tiers
               ),
             :ok <- validate_open_holds(guest.email, event_id),
             {:ok, order} <-
               BookingLocker.atomic_booking(nil, event_id, ticket_selections,
                 guest: guest
               ) do
          {:created, order}
        else
          {:error, reason} ->
            Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, {:created, order}} ->
        Tickets.broadcast_availability(event_id)
        {:ok, order}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # One checkout at a time per (email, event), mirroring the member lock.
  defp lock_guest_event!(email, event_id) do
    Tickets.lock_user_event_ticket_checkout!({:guest, email}, event_id)
  end

  # `max_per_buyer` applies per guest email: tickets already bought for this
  # event with the same address count toward it.
  defp validate_guest_limits(email, event_id, ticket_selections, tiers) do
    attrs =
      Enum.map(tiers, fn tier ->
        %{
          id: tier.id,
          type: tier.type,
          max_per_buyer: tier.max_per_buyer
        }
      end)

    if TierPurchaseLimits.any_limited?(attrs) do
      owned =
        email
        |> owned_by_tier_query(
          event_id,
          TierPurchaseLimits.limited_tier_ids(attrs)
        )
        |> Repo.all()
        |> Map.new()

      TierPurchaseLimits.validate_selection(ticket_selections, attrs, owned)
    else
      :ok
    end
  end

  defp owned_by_tier_query(email, event_id, tier_ids) do
    from(t in Ysc.Events.Ticket,
      join: o in TicketOrder,
      on: o.id == t.ticket_order_id,
      where:
        o.guest_email == ^email and t.event_id == ^event_id and
          t.status == :confirmed and t.ticket_tier_id in ^tier_ids,
      group_by: t.ticket_tier_id,
      select: {t.ticket_tier_id, count(t.id)}
    )
  end

  # An email address is typed by the visitor and proves nothing, so it never
  # lets one checkout cancel another's hold. Holds expire on their own after a
  # few minutes (`TimeoutWorker`); this only stops one address from stacking up
  # many at once.
  @max_open_holds 3

  defp validate_open_holds(email, event_id) do
    now = DateTime.utc_now()

    open =
      Repo.aggregate(
        from(o in TicketOrder,
          where:
            o.guest_email == ^email and o.event_id == ^event_id and
              o.status == :pending and o.expires_at > ^now
        ),
        :count
      )

    if open >= @max_open_holds, do: {:error, :too_many_open_holds}, else: :ok
  end
end
