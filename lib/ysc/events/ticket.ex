defmodule Ysc.Events.Ticket do
  @moduledoc """
  Ticket schema and changesets.

  Defines the Ticket database schema, validations, and changeset functions
  for ticket data manipulation.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ysc.Accounts
  alias Ysc.ReferenceGenerator

  @reference_prefix "TKT"

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "tickets" do
    field :reference_id, :string

    belongs_to :event, Ysc.Events.Event, foreign_key: :event_id, references: :id

    belongs_to :ticket_tier, Ysc.Events.TicketTier,
      foreign_key: :ticket_tier_id,
      references: :id

    belongs_to :user, Ysc.Accounts.User, foreign_key: :user_id, references: :id

    belongs_to :ticket_order, Ysc.Tickets.TicketOrder,
      foreign_key: :ticket_order_id,
      references: :id

    field :status, Ysc.Events.TicketStatus

    belongs_to :payment, Ysc.Ledgers.Payment,
      foreign_key: :payment_id,
      references: :id

    field :expires_at, :utc_datetime
    field :discount_amount, Money.Ecto.Composite.Type, default_currency: :USD

    has_one :registration, Ysc.Events.TicketDetail, foreign_key: :ticket_id

    timestamps()
  end

  @doc """
  Changeset for the ticket with validations.
  """
  def changeset(ticket, attrs) do
    ticket
    |> cast(attrs, [
      :reference_id,
      :event_id,
      :ticket_tier_id,
      :user_id,
      :ticket_order_id,
      :status,
      :payment_id,
      :expires_at,
      :discount_amount
    ])
    |> validate_required([
      :event_id,
      :ticket_tier_id,
      :user_id,
      :expires_at
    ])
    |> validate_active_membership()
    |> validate_event_not_in_past()
    |> put_reference_id()
    |> unique_constraint(:reference_id)
  end

  @doc """
  Changeset for updating ticket status only.
  Skips validations that shouldn't apply when changing status (e.g., expiring tickets).
  This is used for administrative status changes where business validations don't apply.
  """
  def status_changeset(ticket, attrs) do
    ticket
    |> cast(attrs, [:status])
    |> validate_inclusion(:status, [:pending, :confirmed, :expired, :cancelled])
  end

  defp put_reference_id(changeset) do
    case get_field(changeset, :reference_id) do
      nil ->
        put_change(
          changeset,
          :reference_id,
          ReferenceGenerator.generate_reference_id(@reference_prefix)
        )

      _ ->
        changeset
    end
  end

  # Validate that the user has an active membership
  # For sub-accounts, checks the primary user's membership.
  defp validate_active_membership(changeset) do
    user_id = get_field(changeset, :user_id)

    if user_id do
      validate_active_membership_for_user(changeset, user_id)
    else
      changeset
    end
  end

  defp validate_active_membership_for_user(changeset, user_id) do
    # Preload primary_user and subscriptions associations to avoid N+1 queries for sub-accounts
    user = Ysc.Repo.get(Ysc.Accounts.User, user_id)

    case user do
      nil ->
        changeset

      user ->
        user = preload_user_subscriptions(user)
        check_active_membership(changeset, user)
    end
  end

  defp preload_user_subscriptions(user) do
    if Accounts.sub_account?(user) do
      # For sub-accounts, also preload primary user with their subscriptions
      Ysc.Repo.preload(user, [:subscriptions, primary_user: :subscriptions])
    else
      # For primary users, just preload their subscriptions
      Ysc.Repo.preload(user, [:subscriptions])
    end
  end

  defp check_active_membership(changeset, user) do
    # Check if user has an active membership (handles inherited memberships for sub-accounts)
    active_membership = get_active_membership(user)

    if active_membership == nil do
      add_error(
        changeset,
        :user_id,
        "active membership required to purchase tickets"
      )
    else
      changeset
    end
  end

  # Helper function to get the most expensive active membership (same logic as user_auth.ex)
  # For sub-accounts, checks the primary user's membership.
  defp get_active_membership(user) do
    # If user is a sub-account, check primary user's membership
    user_to_check =
      if Accounts.sub_account?(user) do
        # Use preloaded primary_user if available, otherwise fetch it
        case user.primary_user do
          %Ecto.Association.NotLoaded{} ->
            Accounts.get_primary_user(user) || user

          primary_user when not is_nil(primary_user) ->
            primary_user

          _ ->
            Accounts.get_primary_user(user) || user
        end
      else
        user
      end

    # Check for lifetime membership first (highest priority)
    if Accounts.has_lifetime_membership?(user_to_check) do
      # Return a special struct representing lifetime membership
      %{
        type: :lifetime,
        awarded_at: user_to_check.lifetime_membership_awarded_at,
        user_id: user_to_check.id
      }
    else
      # Use preloaded subscriptions if available, otherwise fetch them
      subscriptions =
        case user_to_check.subscriptions do
          %Ecto.Association.NotLoaded{} ->
            # Fallback: fetch subscriptions if not preloaded
            Ysc.Customers.subscriptions(user_to_check)

          subscriptions when is_list(subscriptions) ->
            # Subscriptions are already preloaded
            subscriptions

          _ ->
            []
        end

      # Filter for active subscriptions only
      active_subscriptions =
        Enum.filter(subscriptions, fn subscription ->
          Ysc.Subscriptions.valid?(subscription)
        end)

      case active_subscriptions do
        [] ->
          nil

        [single_subscription] ->
          single_subscription

        multiple_subscriptions ->
          # If multiple active subscriptions, pick the most expensive one
          get_most_expensive_subscription(multiple_subscriptions)
      end
    end
  end

  # Helper function to determine the most expensive subscription
  defp get_most_expensive_subscription(subscriptions) do
    Enum.max_by(subscriptions, fn subscription ->
      # Get the price from the subscription items
      subscription_items =
        case subscription.subscription_items do
          %Ecto.Association.NotLoaded{} ->
            # Preload subscription items if not loaded
            subscription = Ysc.Repo.preload(subscription, :subscription_items)
            subscription.subscription_items

          items when is_list(items) ->
            items

          _ ->
            []
        end

      case subscription_items do
        [item | _] -> item.price.amount
        _ -> 0
      end
    end)
  end

  # Validate that the event is not in the past
  defp validate_event_not_in_past(changeset) do
    event_id = get_field(changeset, :event_id)

    if event_id do
      validate_event_not_ended(changeset, event_id)
    else
      changeset
    end
  end

  defp validate_event_not_ended(changeset, event_id) do
    case Ysc.Repo.get(Ysc.Events.Event, event_id) do
      nil ->
        changeset

      event ->
        now = DateTime.utc_now()
        event_datetime = build_event_datetime(event)

        if DateTime.compare(now, event_datetime) == :gt do
          add_error(
            changeset,
            :event_id,
            "cannot purchase tickets for events that have already ended"
          )
        else
          changeset
        end
    end
  end

  defp build_event_datetime(event) do
    case {event.start_date, event.start_time} do
      {%DateTime{} = date, %Time{} = time} ->
        # Convert DateTime to NaiveDateTime, then combine with time
        naive_date = DateTime.to_naive(date)
        date_part = NaiveDateTime.to_date(naive_date)
        naive_datetime = NaiveDateTime.new!(date_part, time)
        DateTime.from_naive!(naive_datetime, "Etc/UTC")

      {date, time} when not is_nil(date) and not is_nil(time) ->
        # Handle other date/time combinations
        NaiveDateTime.new!(date, time)
        |> DateTime.from_naive!("Etc/UTC")

      _ ->
        # Fallback to just the date if time is nil
        event.start_date
    end
  end
end
