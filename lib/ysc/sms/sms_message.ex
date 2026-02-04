defmodule Ysc.Sms.SmsMessage do
  @moduledoc """
  Schema for outbound SMS messages sent via SMS providers.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "sms_messages" do
    field :provider, SmsProvider
    field :provider_message_id, :string
    field :to, :string
    field :from, :string
    field :body, :string
    field :is_mms, :boolean, default: false
    field :media_urls, {:array, :string}, default: []
    field :status, SmsMessageStatus, default: :sent

    belongs_to :user, Ysc.Accounts.User, foreign_key: :user_id, references: :id

    belongs_to :message_idempotency, Ysc.Messages.MessageIdempotency,
      foreign_key: :message_idempotency_id,
      references: :id

    has_many :delivery_receipts, Ysc.Sms.SmsDeliveryReceipt,
      foreign_key: :sms_message_id

    timestamps()
  end

  @doc false
  def changeset(sms_message, attrs) do
    sms_message
    |> cast(attrs, [
      :provider,
      :provider_message_id,
      :to,
      :from,
      :body,
      :is_mms,
      :media_urls,
      :status,
      :user_id,
      :message_idempotency_id
    ])
    |> validate_required([:provider, :provider_message_id, :to, :from, :body])
    |> unique_constraint([:provider, :provider_message_id])
  end
end
