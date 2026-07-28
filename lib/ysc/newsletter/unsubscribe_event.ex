defmodule Ysc.Newsletter.UnsubscribeEvent do
  @moduledoc """
  Records a confirmed newsletter unsubscribe attributed to a specific edition.

  Written when a subscriber completes unsubscribe via an email link that
  carries an `edition_id` query param. Used for per-edition analytics.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ysc.Newsletter.Edition
  alias Ysc.Newsletter.Subscriber

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "newsletter_unsubscribe_events" do
    belongs_to :edition, Edition
    belongs_to :subscriber, Subscriber

    field :unsubscribed_at, :utc_datetime

    timestamps()
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:edition_id, :subscriber_id, :unsubscribed_at])
    |> validate_required([:edition_id, :subscriber_id, :unsubscribed_at])
    |> foreign_key_constraint(:edition_id)
    |> foreign_key_constraint(:subscriber_id)
    |> unique_constraint([:edition_id, :subscriber_id])
  end
end
