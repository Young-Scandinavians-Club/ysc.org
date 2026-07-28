defmodule Ysc.Messages.MessageIdempotency do
  @moduledoc """
  Message idempotency schema and changesets.

  Defines the MessageIdempotency database schema for ensuring message delivery
  idempotency and preventing duplicate message processing.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "message_idempotency_entries" do
    field :message_type, MessageType

    field :idempotency_key, :string
    field :message_template, :string
    field :params, :map
    field :email, :string
    field :phone_number, :string

    belongs_to :user, Ysc.Accounts.User, foreign_key: :user_id, references: :id

    field :rendered_message, :string

    field :delivery_status, Ecto.Enum,
      values: [:pending, :sending, :accepted, :suppressed, :terminal_failed],
      default: :accepted

    field :delivery_attempts, :integer, default: 0
    field :delivery_lease_expires_at, :utc_datetime
    field :last_delivery_error, :map
    field :provider_message_id, :string
    field :provider_request_id, :string
    field :accepted_at, :utc_datetime

    timestamps()
  end

  def changeset(message_idempotency, attrs) do
    message_idempotency
    |> cast(attrs, [
      :message_type,
      :idempotency_key,
      :message_template,
      :params,
      :email,
      :user_id,
      :phone_number,
      :rendered_message,
      :delivery_status,
      :delivery_attempts,
      :delivery_lease_expires_at,
      :last_delivery_error,
      :provider_message_id,
      :provider_request_id,
      :accepted_at
    ])
    |> validate_required([:message_type, :idempotency_key, :message_template])
    |> unique_constraint(
      [:message_type, :idempotency_key, :message_template],
      name: :message_idempotency_entries_unique_index
    )
  end
end
