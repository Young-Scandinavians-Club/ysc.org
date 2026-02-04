defmodule Ysc.Webhooks.WebhookEvent do
  @moduledoc """
  Webhook event schema and changesets.

  Defines the WebhookEvent database schema, validations, and changeset functions
  for webhook event data manipulation.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "webhook_events" do
    field :provider, WebhookProvider
    field :state, WebhookState, default: :pending

    # External ID of the event used as idempotency check on our end
    # this field has a composite index with provider (provider, event_id).
    # If we receive the same event_id from the same provider, we should ignore it.
    field :event_id, :string
    field :event_type, :string

    field :payload, :map

    timestamps()
  end

  @doc """
  Creates a changeset for a WebhookEvent.
  """
  def changeset(webhook_event, attrs) do
    webhook_event
    |> cast(attrs, [:provider, :state, :event_id, :event_type, :payload])
    |> validate_required([:provider, :event_id, :event_type])
    |> validate_length(:event_id, min: 1)
    |> validate_length(:event_type, min: 1)
    |> unique_constraint([:provider, :event_id],
      name: :webhook_events_provider_event_id_index
    )
    |> validate_inclusion(:state, WebhookState.__valid_values__())
  end
end
