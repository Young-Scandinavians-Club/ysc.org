defmodule Ysc.Sms do
  @moduledoc """
  Context module for managing SMS messages, received messages, and delivery receipts.
  """
  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.Sms.{SmsMessage, SmsReceived, SmsDeliveryReceipt}

  ## SMS Messages (Outbound)

  @doc """
  Creates a new SMS message record for an outbound message.
  """
  def create_sms_message(attrs \\ %{}) do
    %SmsMessage{}
    |> SmsMessage.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets an SMS message by provider and provider message ID.
  """
  def get_sms_message_by_provider_id(provider, provider_message_id) do
    Repo.get_by(SmsMessage,
      provider: provider,
      provider_message_id: provider_message_id
    )
  end

  @doc """
  Updates an SMS message status.
  """
  def update_sms_message_status(sms_message, status) do
    sms_message
    |> Ecto.Changeset.change(status: status)
    |> Repo.update()
  end

  ## SMS Received (Inbound)

  @doc """
  Creates a new SMS received record for an inbound message.
  """
  def create_sms_received(attrs \\ %{}) do
    %SmsReceived{}
    |> SmsReceived.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets an SMS received by provider and provider message ID.
  """
  def get_sms_received_by_provider_id(provider, provider_message_id) do
    Repo.get_by(SmsReceived,
      provider: provider,
      provider_message_id: provider_message_id
    )
  end

  @doc """
  Attempts to match an inbound SMS to a user by phone number.

  Uses normalized phone number matching to handle various formats.
  """
  def match_sms_received_to_user(sms_received) do
    # Use Accounts.get_user_by_phone_number which handles normalization
    case Ysc.Accounts.get_user_by_phone_number(sms_received.from) do
      nil -> {:ok, sms_received}
      user -> update_sms_received_user(sms_received, user.id)
    end
  end

  defp update_sms_received_user(sms_received, user_id) do
    sms_received
    |> Ecto.Changeset.change(user_id: user_id)
    |> Repo.update()
  end

  ## Delivery Receipts (DLRs)

  @doc """
  Creates a new delivery receipt record.
  """
  def create_delivery_receipt(attrs \\ %{}) do
    %SmsDeliveryReceipt{}
    |> SmsDeliveryReceipt.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets delivery receipts for a specific provider message ID.
  """
  def list_delivery_receipts_for_message(provider, provider_message_id) do
    from(dlr in SmsDeliveryReceipt,
      where:
        dlr.provider == ^provider and
          dlr.provider_message_id == ^provider_message_id,
      order_by: [desc: dlr.provider_timestamp]
    )
    |> Repo.all()
  end

  @doc """
  Links a delivery receipt to an SMS message if found.
  """
  def link_delivery_receipt_to_message(delivery_receipt) do
    case get_sms_message_by_provider_id(
           delivery_receipt.provider,
           delivery_receipt.provider_message_id
         ) do
      nil ->
        {:ok, delivery_receipt}

      sms_message ->
        delivery_receipt
        |> Ecto.Changeset.change(sms_message_id: sms_message.id)
        |> Repo.update()
    end
  end
end
