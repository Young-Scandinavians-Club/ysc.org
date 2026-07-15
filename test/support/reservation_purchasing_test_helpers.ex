defmodule Ysc.ReservationPurchasingTestHelpers do
  @moduledoc """
  Shared builders for reservation vs. public ticket purchasing scenarios.
  """

  import Ysc.AccountsFixtures

  alias Ysc.Events
  alias Ysc.Events.{Ticket, TicketReservation}
  alias Ysc.Repo

  @doc """
  User with lifetime membership (required to purchase tickets).
  """
  def membership_user(attrs \\ %{}) do
    user_fixture(attrs)
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at:
        DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> Repo.update!()
  end

  @doc """
  Published event with a single paid tier. Options:

    * `:max_attendees` — event cap (default 100)
    * `:tier_quantity` — tier inventory (default 10)
    * `:tier_price` — `Money` for the tier (default $25)
  """
  def setup_single_tier_event(opts \\ []) do
    organizer = membership_user()
    holder = membership_user()
    stranger = membership_user()

    max_attendees = Keyword.get(opts, :max_attendees, 100)
    tier_quantity = Keyword.get(opts, :tier_quantity, 10)
    tier_price = Keyword.get(opts, :tier_price, Money.new(25, :USD))

    {:ok, event} =
      Events.create_event(%{
        title: "Reservation test event #{System.unique_integer([:positive])}",
        description: "Reservation purchasing integration tests",
        state: :published,
        organizer_id: organizer.id,
        start_date:
          DateTime.add(
            DateTime.utc_now() |> DateTime.truncate(:second),
            30,
            :day
          ),
        max_attendees: max_attendees,
        published_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    {:ok, tier} =
      Events.create_ticket_tier(%{
        name: "General Admission",
        type: :paid,
        price: tier_price,
        quantity: tier_quantity,
        event_id: event.id
      })

    %{
      organizer: organizer,
      holder: holder,
      stranger: stranger,
      event: event,
      tier: tier
    }
  end

  def ticket_expires_at do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.add(1, :day)
  end

  @doc """
  Inserts `:confirmed` tickets against a tier (counts toward sold + event capacity).
  """
  def insert_sold_tickets!(count, %{user: user, event: event, tier: tier}) do
    expires_at = ticket_expires_at()

    for _ <- 1..count do
      %Ticket{
        id: Ecto.ULID.generate(),
        event_id: event.id,
        user_id: user.id,
        ticket_tier_id: tier.id,
        status: :confirmed,
        expires_at: expires_at
      }
      |> Repo.insert!()
    end

    :ok
  end

  @doc """
  Inserts an active ticket reservation hold.
  """
  def insert_reservation!(context, quantity, attrs \\ %{}) do
    holder = Map.fetch!(context, :holder)
    creator = Map.get(context, :organizer, holder)
    tier = Map.fetch!(context, :tier)

    defaults = %{
      ticket_tier_id: tier.id,
      user_id: holder.id,
      quantity: quantity,
      created_by_id: creator.id,
      status: "active"
    }

    %TicketReservation{}
    |> TicketReservation.changeset(Map.merge(defaults, Enum.into(attrs, %{})))
    |> Repo.insert!()
  end

  @doc """
  Inserts a reservation for an arbitrary user (e.g. stranger holds).
  """
  def insert_reservation_for_user!(context, user, quantity, attrs \\ %{}) do
    creator = Map.get(context, :organizer, user)
    tier = Map.fetch!(context, :tier)

    defaults = %{
      ticket_tier_id: tier.id,
      user_id: user.id,
      quantity: quantity,
      created_by_id: creator.id,
      status: "active"
    }

    %TicketReservation{}
    |> TicketReservation.changeset(Map.merge(defaults, Enum.into(attrs, %{})))
    |> Repo.insert!()
  end

  @doc """
  Marks an active reservation as expired while keeping status active (admin lapsed hold).
  """
  def expire_reservation!(reservation) do
    past =
      DateTime.utc_now()
      |> DateTime.add(-3600, :second)
      |> DateTime.truncate(:second)

    reservation
    |> Ecto.Changeset.change(%{expires_at: past})
    |> Repo.update!()
  end

  @doc """
  Public tier availability: quantity − sold − all active reservations.
  """
  def public_tier_available(tier) do
    sold = Events.count_tickets_for_tier(tier.id)
    reserved = Events.count_reserved_tickets_for_tier(tier.id)
    max(0, tier.quantity - sold - reserved)
  end

  @doc """
  Tier availability for a specific user (adds their holds back).
  """
  def user_tier_available(tier, user_id) do
    public = public_tier_available(tier)
    user_reserved = Events.get_user_reserved_quantity(tier.id, user_id)
    public + user_reserved
  end
end
