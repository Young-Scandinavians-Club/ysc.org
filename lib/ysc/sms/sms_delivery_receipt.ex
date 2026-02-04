defmodule Ysc.Sms.SmsDeliveryReceipt do
  @moduledoc """
  Schema for delivery receipts (DLRs) from SMS providers.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "sms_delivery_receipts" do
    field :provider, SmsProvider
    field :provider_message_id, :string
    field :body, :string
    field :level, :integer
    field :status, SmsDeliveryReceiptStatus
    field :status_code, :string
    field :status_code_description, :string
    field :provider_timestamp, :utc_datetime
    field :raw_payload, :map

    belongs_to :sms_message, Ysc.Sms.SmsMessage,
      foreign_key: :sms_message_id,
      references: :id

    timestamps()
  end

  @doc false
  def changeset(sms_delivery_receipt, attrs) do
    sms_delivery_receipt
    |> cast(attrs, [
      :provider,
      :provider_message_id,
      :body,
      :level,
      :status,
      :status_code,
      :status_code_description,
      :provider_timestamp,
      :raw_payload,
      :sms_message_id
    ])
    |> validate_required([:provider, :provider_message_id, :status])
    |> unique_constraint([:provider, :provider_message_id, :provider_timestamp],
      name: :sms_delivery_receipts_provider_message_timestamp_unique
    )
  end
end
