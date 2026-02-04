defmodule Ysc.Sms.SmsReceived do
  @moduledoc """
  Schema for inbound SMS messages received via SMS provider webhooks.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "sms_received" do
    field :provider, SmsProvider
    field :provider_message_id, :string
    field :from, :string
    field :to, :string
    field :body, :string
    field :is_mms, :boolean, default: false
    field :direction, SmsDirection, default: :inbound
    field :message_type, :string
    field :message_encoding, :integer
    field :status, SmsReceivedStatus
    field :amount_display, :string
    field :amount_nanodollars, :integer
    field :message_callback_url, :string
    field :provider_timestamp, :utc_datetime
    field :raw_payload, :map

    belongs_to :user, Ysc.Accounts.User, foreign_key: :user_id, references: :id

    timestamps()
  end

  @doc false
  def changeset(sms_received, attrs) do
    sms_received
    |> cast(attrs, [
      :provider,
      :provider_message_id,
      :from,
      :to,
      :body,
      :is_mms,
      :direction,
      :message_type,
      :message_encoding,
      :status,
      :amount_display,
      :amount_nanodollars,
      :message_callback_url,
      :provider_timestamp,
      :raw_payload,
      :user_id
    ])
    |> validate_required([:provider, :provider_message_id, :from, :to])
    |> unique_constraint([:provider, :provider_message_id])
  end
end
