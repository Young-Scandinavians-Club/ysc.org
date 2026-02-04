defmodule Ysc.Subscriptions.Subscription do
  @moduledoc """
  Subscription schema and changesets.

  Defines the Subscription database schema, validations, and changeset functions
  for subscription data manipulation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "subscriptions" do
    field :name, :string
    field :ends_at, :utc_datetime
    field :trial_ends_at, :utc_datetime

    field :stripe_id, :string
    field :stripe_status, :string

    field :start_date, :utc_datetime
    field :current_period_start, :utc_datetime
    field :current_period_end, :utc_datetime

    belongs_to :user, Ysc.Accounts.User, foreign_key: :user_id, references: :id

    has_many :subscription_items, Ysc.Subscriptions.SubscriptionItem

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [
      :name,
      :ends_at,
      :trial_ends_at,
      :stripe_id,
      :stripe_status,
      :start_date,
      :current_period_start,
      :current_period_end,
      :user_id
    ])
    |> validate_required([:stripe_id, :stripe_status, :user_id])
    |> unique_constraint(:stripe_id)
    |> foreign_key_constraint(:user_id)
  end
end
