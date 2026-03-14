defmodule Ysc.Events.EventNotificationSubscription do
  @moduledoc """
  Tracks opt-in notification subscriptions for events.

  A user can subscribe to a specific notification type for an event.
  Supported types:
  - "save_the_date" — notify when tickets_tbd is cleared (event becomes bookable)
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "event_notification_subscriptions" do
    belongs_to :event, Ysc.Events.Event
    belongs_to :user, Ysc.Accounts.User

    field :notification_type, :string

    timestamps()
  end

  @valid_types ~w(save_the_date)

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:event_id, :user_id, :notification_type])
    |> validate_required([:event_id, :user_id, :notification_type])
    |> validate_inclusion(:notification_type, @valid_types)
    |> unique_constraint([:event_id, :user_id, :notification_type])
  end
end
