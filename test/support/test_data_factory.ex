defmodule Ysc.TestDataFactory do
  @moduledoc """
  Comprehensive test data factory for setting up complex test scenarios.

  This module provides high-level helpers that combine fixtures to create
  realistic test data for various scenarios including:

  - Users with different membership states
  - Family accounts with primary and sub-accounts
  - Complete ticket orders with events, tiers, and payments
  - Bookings with various configurations
  - Events in different states

  ## Usage Examples

      # User with lifetime membership
      user = TestDataFactory.user_with_membership(:lifetime)

      # Family with primary user and 2 sub-accounts
      family = TestDataFactory.family_with_sub_accounts(2)

      # Complete ticket order with event and tickets
      order_data = TestDataFactory.complete_ticket_order()

      # Upcoming event with tickets available
      event = TestDataFactory.event_with_tickets(:upcoming)
  """

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.TicketsFixtures
  import Ysc.BookingsFixtures, only: []

  alias Ysc.Repo
  alias Ysc.Media

  @doc """
  Creates a user with a specific membership configuration.

  ## Options

  - `:lifetime` - User with lifetime membership
  - `:subscription` - User with active Stripe subscription (mock)
  - `:none` - User with no membership

  Additional attrs can be passed to customize the user.

  ## Examples

      user = user_with_membership(:lifetime)
      user = user_with_membership(:lifetime, %{first_name: "Alice"})
      user = user_with_membership(:none)
  """
  def user_with_membership(type \\ :lifetime, attrs \\ %{})

  def user_with_membership(:lifetime, attrs) do
    user = user_fixture(attrs)

    {:ok, user} =
      user
      |> Ecto.Changeset.change(%{
        lifetime_membership_awarded_at:
          DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update()

    user
  end

  def user_with_membership(:subscription, attrs) do
    # Create user and set up mock subscription
    # Note: In real tests, you'd mock the Stripe API calls
    user =
      user_fixture(
        Map.put(attrs, :stripe_id, "cus_test_#{System.unique_integer()}")
      )

    user
  end

  def user_with_membership(:none, attrs) do
    user_fixture(attrs)
  end

  @doc """
  Creates a family account structure with a primary user and sub-accounts.

  Returns a map with:
  - `:primary` - The primary user (with membership)
  - `:sub_accounts` - List of sub-account users

  ## Options

  - `count` - Number of sub-accounts to create (default: 2)
  - `primary_attrs` - Attributes for the primary user
  - `sub_account_attrs` - Base attributes for sub-accounts

  ## Examples

      family = family_with_sub_accounts()
      family = family_with_sub_accounts(3)
      family = family_with_sub_accounts(2, %{first_name: "Primary"}, %{last_name: "Child"})
  """
  def family_with_sub_accounts(
        count \\ 2,
        primary_attrs \\ %{},
        sub_account_attrs \\ %{}
      ) do
    # Create primary user with membership
    primary =
      primary_attrs
      |> Map.put(:role, "member")
      |> user_with_membership(:lifetime)

    # Create sub-accounts linked to primary
    sub_accounts =
      Enum.map(1..count, fn i ->
        attrs =
          sub_account_attrs
          |> Map.merge(%{
            first_name: "Sub#{i}",
            last_name: primary.last_name,
            primary_user_id: primary.id,
            role: "sub_account"
          })

        user_fixture(attrs)
      end)

    %{
      primary: primary,
      sub_accounts: sub_accounts
    }
  end

  @doc """
  Creates an event with specified state and optional image.

  ## States

  - `:upcoming` - Event in the future (default)
  - `:past` - Event that has ended
  - `:cancelled` - Cancelled event
  - `:ongoing` - Event happening now

  ## Options

  - `with_image: true` - Include a test image
  - `attrs` - Additional event attributes

  ## Examples

      event = event_with_state(:upcoming)
      event = event_with_state(:past, with_image: true)
      event = event_with_state(:cancelled, attrs: %{title: "Cancelled Party"})
  """
  def event_with_state(state \\ :upcoming, opts \\ []) do
    attrs = Keyword.get(opts, :attrs, %{})
    with_image = Keyword.get(opts, :with_image, false)

    # Create image if requested
    image =
      if with_image do
        create_test_image()
      else
        nil
      end

    # Set dates based on state
    {start_date, end_date, event_state} =
      case state do
        :upcoming ->
          {
            DateTime.add(DateTime.utc_now(), 7, :day)
            |> DateTime.truncate(:second),
            DateTime.add(DateTime.utc_now(), 8, :day)
            |> DateTime.truncate(:second),
            :published
          }

        :past ->
          {
            DateTime.add(DateTime.utc_now(), -8, :day)
            |> DateTime.truncate(:second),
            DateTime.add(DateTime.utc_now(), -7, :day)
            |> DateTime.truncate(:second),
            :published
          }

        :ongoing ->
          {
            DateTime.add(DateTime.utc_now(), -1, :day)
            |> DateTime.truncate(:second),
            DateTime.add(DateTime.utc_now(), 1, :day)
            |> DateTime.truncate(:second),
            :published
          }

        :cancelled ->
          {
            DateTime.add(DateTime.utc_now(), 7, :day)
            |> DateTime.truncate(:second),
            DateTime.add(DateTime.utc_now(), 8, :day)
            |> DateTime.truncate(:second),
            :cancelled
          }
      end

    event_attrs =
      attrs
      |> Map.merge(%{
        start_date: start_date,
        end_date: end_date,
        state: event_state,
        image_id: if(image, do: image.id, else: nil)
      })

    event_fixture(event_attrs)
  end

  @doc """
  Creates an event with ticket tiers ready for purchase.

  ## Options

  - `tier_count` - Number of ticket tiers (default: 2)
  - `state` - Event state (default: :upcoming)
  - `event_attrs` - Additional event attributes
  - `tier_attrs` - Base attributes for tiers

  ## Examples

      event = event_with_tickets()
      event = event_with_tickets(tier_count: 3, state: :upcoming)
  """
  def event_with_tickets(opts \\ []) do
    tier_count = Keyword.get(opts, :tier_count, 2)
    state = Keyword.get(opts, :state, :upcoming)
    event_attrs = Keyword.get(opts, :event_attrs, %{})
    tier_attrs = Keyword.get(opts, :tier_attrs, %{})

    event = event_with_state(state, with_image: true, attrs: event_attrs)

    # Create ticket tiers
    tiers =
      Enum.map(1..tier_count, fn i ->
        attrs =
          tier_attrs
          |> Map.merge(%{
            event_id: event.id,
            name: "Tier #{i}",
            type: :paid,
            price: Money.new(i * 2500, :USD),
            quantity: 100
          })

        ticket_tier_fixture(attrs)
      end)

    # Reload event with tiers
    event = Repo.preload(event, :ticket_tiers, force: true)
    Map.put(event, :tiers, tiers)
  end

  @doc """
  Creates a complete ticket order with all associations.

  Returns a map with:
  - `:user` - User who made the order (with membership)
  - `:event` - Event for the tickets
  - `:tiers` - Ticket tiers
  - `:order` - TicketOrder record
  - `:tickets` - Individual ticket records

  ## Options

  - `user` - Use existing user (will add membership if needed)
  - `event` - Use existing event
  - `ticket_count` - Number of tickets (default: 2)
  - `status` - Order status (default: :confirmed)
  - `user_attrs` - Attributes for new user
  - `event_attrs` - Attributes for new event

  ## Examples

      data = complete_ticket_order()
      data = complete_ticket_order(ticket_count: 3, status: :completed)
      data = complete_ticket_order(user: my_user, event: my_event)
  """
  def complete_ticket_order(opts \\ []) do
    # Get or create user with membership
    user =
      case Keyword.get(opts, :user) do
        nil ->
          user_attrs = Keyword.get(opts, :user_attrs, %{})
          user_with_membership(:lifetime, user_attrs)

        user ->
          # Ensure user has membership
          user_with_membership(:lifetime, %{id: user.id})
      end

    # Get or create event
    event =
      case Keyword.get(opts, :event) do
        nil ->
          event_attrs = Keyword.get(opts, :event_attrs, %{})
          event_with_state(:upcoming, attrs: event_attrs)

        event ->
          event
      end

    # Create ticket tiers
    ticket_count = Keyword.get(opts, :ticket_count, 2)

    tiers =
      Enum.map(1..ticket_count, fn i ->
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "Tier #{i}",
          type: :paid,
          price: Money.new(i * 2500, :USD),
          quantity: 100
        })
      end)

    # Build ticket selections
    ticket_selections = Map.new(tiers, fn tier -> {tier.id, 1} end)

    # Create order using the fixtures (which handles membership)
    order_status = Keyword.get(opts, :status, :confirmed)

    order =
      ticket_order_fixture(%{
        user: user,
        event: event,
        tier: hd(tiers),
        ticket_selections: ticket_selections,
        status: order_status
      })

    # Reload with all associations
    order =
      Repo.preload(order, [
        :user,
        :event,
        :payment,
        tickets: [:ticket_tier, :registration]
      ])

    %{
      user: user,
      event: event,
      tiers: tiers,
      order: order,
      tickets: order.tickets
    }
  end

  @doc """
  Creates a test image for events or other entities.

  Returns a Media.Image struct.
  """
  def create_test_image(attrs \\ %{}) do
    uploader = user_fixture()

    default_attrs = %{
      title: "Test Image #{System.unique_integer()}",
      raw_image_path: "/uploads/test_image.jpg",
      optimized_image_path: "/uploads/test_image_optimized.jpg",
      thumbnail_path: "/uploads/test_image_thumb.jpg",
      blur_hash: "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
      user_id: uploader.id
    }

    attrs = Map.merge(default_attrs, attrs)

    {:ok, image} =
      %Media.Image{}
      |> Media.Image.add_image_changeset(attrs)
      |> Repo.insert()

    image
  end

  @doc """
  Creates a booking scenario with property, dates, and optional state.

  ## States

  - `:upcoming` - Booking in the future
  - `:ongoing` - Booking happening now
  - `:past` - Completed booking
  - `:cancelled` - Cancelled booking

  ## Examples

      booking = booking_scenario(:upcoming, property: :tahoe)
      booking = booking_scenario(:past, property: :clear_lake)
  """
  def booking_scenario(state \\ :upcoming, opts \\ []) do
    # Note: Implement based on your bookings domain
    # This is a placeholder showing the pattern
    property = Keyword.get(opts, :property, :tahoe)
    user = Keyword.get(opts, :user) || user_with_membership(:lifetime)

    {check_in, check_out, booking_state} =
      case state do
        :upcoming ->
          {
            Date.add(Date.utc_today(), 30),
            Date.add(Date.utc_today(), 33),
            :confirmed
          }

        :ongoing ->
          {
            Date.add(Date.utc_today(), -1),
            Date.add(Date.utc_today(), 2),
            :confirmed
          }

        :past ->
          {
            Date.add(Date.utc_today(), -10),
            Date.add(Date.utc_today(), -7),
            :completed
          }

        :cancelled ->
          {
            Date.add(Date.utc_today(), 30),
            Date.add(Date.utc_today(), 33),
            :cancelled
          }
      end

    %{
      user: user,
      property: property,
      check_in: check_in,
      check_out: check_out,
      state: booking_state
    }
  end
end
