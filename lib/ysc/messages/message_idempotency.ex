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
      :rendered_message
    ])
    |> validate_required([:message_type, :idempotency_key, :message_template])
    |> unique_constraint(
      [:message_type, :idempotency_key, :message_template],
      name: :message_idempotency_entries_unique_index
    )
  end
end
