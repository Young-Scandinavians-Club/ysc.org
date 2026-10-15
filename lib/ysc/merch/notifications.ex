defmodule Ysc.Merch.Notifications do
  @moduledoc """
  Emails and texts about merch order progress.

  Email jobs are added to the same `Ecto.Multi` as the state change that
  triggers them, so an order can't change state without its notification (or
  the reverse). SMS goes out right after that transaction commits; it is
  best-effort and idempotent, and only sent to a member who has a phone number
  and hasn't opted out. Admin orders to a custom address (no member) get email
  only, since there is no consent to text that number.

  Every job has an idempotency key, so retries and duplicate events never send
  twice.
  """
  require Ysc.Logging

  alias Ecto.Multi
  alias Ysc.Accounts.SmsCategories
  alias Ysc.Merch.{Order, Shipment}

  alias YscWeb.Emails.{MerchOrderAttentionBoardNotification, Notifier}
  alias YscWeb.Sms.Notifier, as: SmsNotifier

  ## Email (added to a Multi)

  @doc """
  Adds the "your order shipped" email for `shipment` to `multi`. No-op when
  the order has no email address.
  """
  def put_shipped_email(multi, %Order{} = order, %Shipment{} = shipment) do
    case recipient_email(order) do
      nil ->
        multi

      email ->
        Notifier.schedule_email_multi(multi, :shipped_email, %{
          recipient: email,
          idempotency_key: "merch_order_shipped_#{shipment.id}",
          subject: YscWeb.Emails.MerchOrderShipped.get_subject(order),
          template: YscWeb.Emails.MerchOrderShipped.get_template_name(),
          variables:
            YscWeb.Emails.MerchOrderShipped.prepare_email_data(order, shipment),
          text_body: "",
          user_id: order.user_id
        })
    end
  end

  @doc """
  Adds a member update email (`:delivered`, `:returned`, `:failed`,
  `:canceled`) to `multi`. `suffix` distinguishes repeats of one kind, e.g. a
  return per shipment.
  """
  def put_update_email(multi, %Order{} = order, kind, suffix \\ nil) do
    case recipient_email(order) do
      nil ->
        multi

      email ->
        Notifier.schedule_email_multi(multi, :update_email, %{
          recipient: email,
          idempotency_key:
            ["merch_order_update", order.id, kind, suffix]
            |> Enum.reject(&is_nil/1)
            |> Enum.join("_"),
          subject: YscWeb.Emails.MerchOrderUpdate.get_subject(kind, order),
          template: YscWeb.Emails.MerchOrderUpdate.get_template_name(),
          variables:
            YscWeb.Emails.MerchOrderUpdate.prepare_email_data(kind, order),
          text_body: "",
          user_id: order.user_id
        })
    end
  end

  @doc """
  Adds an alert to the board to `multi`. `kind` is `:submit_failed`,
  `:failed`, `:canceled`, `:on_hold`, `:needs_approval`, `:refunded` or
  `:returned`.
  """
  def put_attention_email(multi, %Order{} = order, kind, reason, suffix \\ nil) do
    key =
      ["merch_order_attention", order.id, kind, suffix]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("_")

    # Addressed to the board explicitly. (`Notifier.schedule_email_to_board_multi/7`
    # sends to the *from* address, which is not what an alert like this needs.)
    Notifier.schedule_email_multi(multi, :attention_email, %{
      recipient: Ysc.EmailConfig.board_email(),
      idempotency_key: key,
      subject: MerchOrderAttentionBoardNotification.get_subject(kind, order),
      template: MerchOrderAttentionBoardNotification.get_template_name(),
      variables:
        MerchOrderAttentionBoardNotification.prepare_email_data(
          kind,
          order,
          reason
        ),
      text_body: "",
      user_id: nil
    })
  end

  @doc """
  Alerts the board about an order outside of any other state change (e.g. a
  hold, which changes nothing in our database).
  """
  def alert_board(%Order{} = order, kind, reason, suffix \\ nil) do
    Multi.new()
    |> put_attention_email(order, kind, reason, suffix)
    |> Ysc.Repo.transaction()
    |> case do
      {:ok, _} ->
        :ok

      {:error, _step, reason, _} ->
        Ysc.Logging.error("Could not alert the board about a merch order",
          extra: %{order_id: order.id, kind: kind, reason: inspect(reason)}
        )

        {:error, reason}
    end
  end

  ## SMS (after the transaction commits)

  @doc "Texts the member that a shipment is on its way."
  def send_shipped_sms(%Order{} = order, %Shipment{} = shipment) do
    send_sms(
      order,
      YscWeb.Sms.MerchOrderShipped.get_template_name(),
      "merch_order_shipped_sms_#{shipment.id}",
      YscWeb.Sms.MerchOrderShipped.prepare_sms_data(
        order,
        shipment,
        first_name(order)
      )
    )
  end

  @doc "Texts the member an update (`:delivered`, `:returned`, `:failed`, `:canceled`)."
  def send_update_sms(%Order{} = order, kind, suffix \\ nil) do
    key =
      ["merch_order_update_sms", order.id, kind, suffix]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("_")

    send_sms(
      order,
      YscWeb.Sms.MerchOrderUpdate.get_template_name(),
      key,
      YscWeb.Sms.MerchOrderUpdate.prepare_sms_data(
        kind,
        order,
        first_name(order)
      )
    )
  end

  defp send_sms(%Order{user: %{} = user} = order, template, key, data) do
    if SmsCategories.should_send_sms?(user, template) and
         SmsCategories.has_phone_number?(user) do
      case SmsNotifier.schedule_sms(
             user.phone_number,
             key,
             template,
             data,
             user.id
           ) do
        {:ok, _job} ->
          :ok

        {:error, reason} ->
          Ysc.Logging.warning("Merch SMS not scheduled",
            order_id: order.id,
            template: template,
            reason: inspect(reason)
          )

          :ok
      end
    else
      :ok
    end
  end

  defp send_sms(_order_without_member, _template, _key, _data), do: :ok

  defp recipient_email(%Order{email: email})
       when is_binary(email) and email != "", do: email

  defp recipient_email(%Order{user: %{email: email}}) when is_binary(email),
    do: email

  defp recipient_email(_), do: nil

  defp first_name(%Order{user: %{first_name: name}}), do: name
  defp first_name(_), do: nil
end
