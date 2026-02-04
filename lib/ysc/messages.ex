defmodule Ysc.Messages do
  @moduledoc """
  Context module for managing messages and idempotency.

  Handles creation and tracking of messages with idempotency guarantees.
  """
  require Logger
  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.Messages.MessageIdempotency

  alias Ysc.Mailer
  alias Ysc.Flowroute.Client
  alias Ysc.SmsRateLimit

  # Helper function to safely convert email recipient to string
  defp email_recipient_to_string(recipient) when is_binary(recipient),
    do: recipient

  defp email_recipient_to_string({_name, email}) when is_binary(email),
    do: email

  defp email_recipient_to_string([recipient | _]),
    do: email_recipient_to_string(recipient)

  defp email_recipient_to_string(other), do: inspect(other)

  def create_message_idempotency(attrs) do
    %MessageIdempotency{}
    |> MessageIdempotency.changeset(attrs)
    |> Repo.insert()
  end

  def run_send_message_idempotent(email, attrs) do
    Logger.debug("run_send_message_idempotent called",
      recipient: email.to,
      idempotency_key: attrs[:idempotency_key],
      message_template: attrs[:message_template]
    )

    try do
      result = build_and_run_email_transaction(email, attrs)
      handle_email_transaction_result(result, email, attrs)
    rescue
      error in [Ecto.ConstraintError] ->
        handle_email_constraint_error(error, email, attrs)

      error ->
        handle_email_transaction_exception(error, email, attrs, __STACKTRACE__)
    end
  end

  defp build_and_run_email_transaction(email, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(
      :message_idempotency,
      MessageIdempotency.changeset(%MessageIdempotency{}, attrs)
    )
    |> Ecto.Multi.run(:send_email, fn repo, _result ->
      send_email_via_mailer(email, attrs, repo)
    end)
    |> Repo.transaction()
  end

  defp send_email_via_mailer(email, attrs, repo) do
    Logger.debug("Sending email via Mailer.deliver",
      recipient: email.to,
      idempotency_key: attrs[:idempotency_key]
    )

    case Mailer.deliver(email) do
      {:ok, _metadata} ->
        Logger.debug("Mailer.deliver succeeded",
          recipient: email.to,
          idempotency_key: attrs[:idempotency_key]
        )

        {:ok, email}

      error ->
        handle_mailer_deliver_error(error, email, attrs, repo)
    end
  end

  defp handle_mailer_deliver_error(error, email, attrs, repo) do
    Logger.error("Mailer.deliver failed",
      recipient: email.to,
      idempotency_key: attrs[:idempotency_key],
      error: inspect(error)
    )

    Sentry.capture_message("Mailer.deliver failed",
      level: :error,
      extra:
        build_email_sentry_extra(email, attrs, %{
          error: inspect(error, limit: :infinity)
        }),
      tags: build_email_sentry_tags(attrs, "mailer_deliver_failed")
    )

    repo.rollback({:error, "failed to send email"})
    {:error, "failed to send email"}
  end

  defp handle_email_transaction_result(result, email, attrs) do
    case result do
      {:ok, %{send_email: email}} ->
        handle_successful_email(email, attrs)

      {:error, :message_idempotency, changeset, _} ->
        handle_email_idempotency_duplicate(email, attrs, changeset)

      {:error, operation, reason, _changes} ->
        handle_email_transaction_error(email, attrs, operation, reason)

      error ->
        handle_unexpected_email_error(email, attrs, error)
    end
  end

  defp handle_successful_email(email, attrs) do
    Logger.debug("Email transaction succeeded",
      recipient: email.to,
      idempotency_key: attrs[:idempotency_key]
    )

    emit_email_sent_telemetry(email, attrs, %{})
    {:ok, email}
  end

  defp handle_email_idempotency_duplicate(email, attrs, changeset) do
    Logger.info("Duplicate message detected (idempotency), treating as success",
      recipient: email.to,
      idempotency_key: attrs[:idempotency_key],
      errors: inspect(changeset.errors)
    )

    emit_email_sent_telemetry(email, attrs, %{duplicate: true})
    {:ok, email}
  end

  defp handle_email_transaction_error(email, attrs, operation, reason) do
    Logger.error("Email transaction failed",
      recipient: email.to,
      idempotency_key: attrs[:idempotency_key],
      operation: operation,
      reason: inspect(reason)
    )

    Sentry.capture_message("Email transaction failed",
      level: :error,
      extra:
        build_email_sentry_extra(email, attrs, %{
          operation: to_string(operation),
          reason: inspect(reason, limit: :infinity)
        }),
      tags:
        build_email_sentry_tags(attrs, "email_transaction_failed", %{
          operation: to_string(operation)
        })
    )

    emit_email_send_failed_telemetry(email, attrs, %{
      operation: to_string(operation),
      reason: inspect(reason)
    })

    {:error, "failed to send email"}
  end

  defp handle_unexpected_email_error(email, attrs, error) do
    Logger.error("Email transaction failed with unexpected error",
      recipient: email.to,
      idempotency_key: attrs[:idempotency_key],
      error: inspect(error)
    )

    Sentry.capture_message("Email transaction failed with unexpected error",
      level: :error,
      extra:
        build_email_sentry_extra(email, attrs, %{
          error: inspect(error, limit: :infinity)
        }),
      tags: build_email_sentry_tags(attrs, "email_transaction_unexpected_error")
    )

    emit_email_send_failed_telemetry(email, attrs, %{error: inspect(error)})
    {:error, "failed to send email"}
  end

  defp handle_email_constraint_error(error, email, attrs) do
    if error.type == :unique do
      handle_email_unique_constraint_error(error, email, attrs)
    else
      handle_email_non_unique_constraint_error(error, email, attrs)
    end
  end

  defp handle_email_unique_constraint_error(error, email, attrs) do
    constraint_string = to_string(error.constraint)

    idempotency_constraint_names = [
      "message_idempotency_entries_unique_index",
      "message_idempotency_entries_message_type_idempotency_key_messag"
    ]

    if constraint_string in idempotency_constraint_names do
      handle_email_idempotency_constraint_duplicate(
        email,
        attrs,
        constraint_string
      )
    else
      handle_email_non_idempotency_unique_constraint(
        error,
        email,
        attrs,
        constraint_string
      )
    end
  end

  defp handle_email_idempotency_constraint_duplicate(
         email,
         attrs,
         constraint_string
       ) do
    Logger.info(
      "Duplicate message detected (idempotency constraint), treating as success",
      recipient: email.to,
      idempotency_key: attrs[:idempotency_key],
      constraint: constraint_string
    )

    emit_email_sent_telemetry(email, attrs, %{duplicate: true})
    {:ok, email}
  end

  defp handle_email_non_idempotency_unique_constraint(
         error,
         email,
         attrs,
         constraint_string
       ) do
    Logger.error(
      "Email transaction raised unique constraint error (not idempotency)",
      recipient: email.to,
      idempotency_key: attrs[:idempotency_key],
      constraint: constraint_string,
      error: inspect(error)
    )

    Sentry.capture_exception(error,
      extra:
        build_email_sentry_extra(email, attrs, %{
          constraint: constraint_string,
          constraint_type: error.type
        }),
      tags:
        build_email_sentry_tags(attrs, "unique_constraint_error", %{
          constraint: constraint_string
        })
    )

    emit_email_send_failed_telemetry(email, attrs, %{
      constraint: constraint_string,
      error: inspect(error)
    })

    {:error, "failed to send email"}
  end

  defp handle_email_non_unique_constraint_error(error, email, attrs) do
    Logger.error("Email transaction raised constraint error (not unique)",
      recipient: email.to,
      idempotency_key: attrs[:idempotency_key],
      constraint: error.constraint,
      type: error.type,
      error: inspect(error)
    )

    Sentry.capture_exception(error,
      extra:
        build_email_sentry_extra(email, attrs, %{
          constraint: to_string(error.constraint),
          constraint_type: error.type
        }),
      tags:
        build_email_sentry_tags(attrs, "constraint_error", %{
          constraint: to_string(error.constraint)
        })
    )

    emit_email_send_failed_telemetry(email, attrs, %{
      constraint: to_string(error.constraint),
      error: inspect(error)
    })

    {:error, "failed to send email"}
  end

  defp handle_email_transaction_exception(error, email, attrs, stacktrace) do
    Logger.error("Email transaction raised exception",
      recipient: email.to,
      idempotency_key: attrs[:idempotency_key],
      error: inspect(error),
      stacktrace: Exception.format_stacktrace(stacktrace)
    )

    Sentry.capture_exception(error,
      stacktrace: stacktrace,
      extra:
        build_email_sentry_extra(email, attrs, %{
          error_type: inspect(error.__struct__),
          error_message: Exception.message(error)
        }),
      tags: build_email_sentry_tags(attrs, "email_transaction_exception")
    )

    emit_email_send_failed_telemetry(email, attrs, %{error: inspect(error)})
    {:error, "failed to send email"}
  end

  defp build_email_sentry_extra(email, attrs, additional) do
    Map.merge(
      %{
        recipient: email_recipient_to_string(email.to),
        idempotency_key: attrs[:idempotency_key],
        message_template: attrs[:message_template],
        user_id: attrs[:user_id],
        email_subject: email.subject
      },
      additional
    )
  end

  defp build_email_sentry_tags(attrs, error_type, additional \\ %{}) do
    Map.merge(
      %{
        email_template: attrs[:message_template] || "unknown",
        error_type: error_type,
        has_user_id: !is_nil(attrs[:user_id])
      },
      additional
    )
  end

  defp build_email_telemetry_metadata(email, attrs, additional) do
    Map.merge(
      %{
        template: attrs[:message_template] || "unknown",
        recipient: email_recipient_to_string(email.to),
        idempotency_key: attrs[:idempotency_key] || nil
      },
      additional
    )
  end

  defp emit_email_sent_telemetry(email, attrs, additional) do
    :telemetry.execute(
      [:ysc, :email, :sent],
      %{count: 1},
      build_email_telemetry_metadata(email, attrs, additional)
    )
  end

  defp emit_email_send_failed_telemetry(email, attrs, additional) do
    :telemetry.execute(
      [:ysc, :email, :send_failed],
      %{count: 1},
      build_email_telemetry_metadata(email, attrs, additional)
    )
  end

  @doc """
  Lists all messages (notifications) for a user, ordered by most recent first.
  """
  def list_user_messages(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    from(m in MessageIdempotency,
      where: m.user_id == ^user_id,
      order_by: [desc: m.id],
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
  end

  @doc """
  Gets the total count of messages for a user.
  """
  def count_user_messages(user_id) do
    from(m in MessageIdempotency,
      where: m.user_id == ^user_id,
      select: count()
    )
    |> Repo.one()
  end

  @doc """
  Sends an SMS message with idempotency handling.

  This function ensures that duplicate SMS messages are not sent by using
  the message idempotency system. If a message with the same idempotency key
  and template has already been sent, it will be treated as a success.

  ## Parameters

    - `phone_number` (required) - Recipient phone number in 11-digit North American format
    - `body` (required) - Message content
    - `attrs` (required) - Map containing:
      - `:idempotency_key` (required) - Unique key for idempotency
      - `:message_template` (required) - Template identifier
      - `:user_id` (optional) - User ID if associated with a user
      - `:params` (optional) - Additional parameters
      - `:from` (optional) - Sender phone number (defaults to configured FlowRoute number)

  ## Returns

    - `{:ok, %{id: message_id}}` - Success with FlowRoute message ID
    - `{:error, reason}` - Error with reason

  ## Examples

      {:ok, %{id: "mdr2-..."}} =
        Ysc.Messages.run_send_sms_idempotent(
          "12065551234",
          "Your booking confirmation",
          idempotency_key: "booking_123",
          message_template: "booking_confirmation",
          user_id: user.id,
          params: %{booking_id: 123}
        )
  """
  @spec run_send_sms_idempotent(String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def run_send_sms_idempotent(phone_number, body, attrs) do
    Logger.debug("run_send_sms_idempotent called",
      recipient: phone_number,
      idempotency_key: attrs[:idempotency_key],
      message_template: attrs[:message_template]
    )

    with {:ok, :allowed} <- check_rate_limit(phone_number, attrs) do
      execute_sms_transaction(phone_number, body, attrs)
    end
  end

  defp check_rate_limit(phone_number, attrs) do
    case SmsRateLimit.check_rate_limit(phone_number) do
      {:error, :rate_limit_exceeded, reason} ->
        handle_rate_limit_exceeded(phone_number, attrs, reason)
        {:error, reason}

      {:ok, :allowed} ->
        {:ok, :allowed}
    end
  end

  defp handle_rate_limit_exceeded(phone_number, attrs, reason) do
    Logger.warning("SMS rate limit check failed",
      recipient: phone_number,
      idempotency_key: attrs[:idempotency_key],
      reason: reason
    )

    Sentry.capture_message("SMS rate limit exceeded",
      level: :warning,
      extra: build_sentry_extra(phone_number, attrs, %{reason: reason}),
      tags: build_sentry_tags(attrs, "sms_rate_limit_exceeded")
    )

    :telemetry.execute(
      [:ysc, :sms, :rate_limit_exceeded],
      %{count: 1},
      build_telemetry_metadata(phone_number, attrs, %{reason: reason})
    )
  end

  defp execute_sms_transaction(phone_number, body, attrs) do
    try do
      result = build_and_run_sms_transaction(phone_number, body, attrs)
      handle_transaction_result(result, phone_number, attrs, body)
    rescue
      error in [Ecto.ConstraintError] ->
        handle_constraint_error(error, phone_number, attrs, body)

      error ->
        handle_transaction_exception(
          error,
          phone_number,
          attrs,
          body,
          __STACKTRACE__
        )
    end
  end

  defp handle_transaction_exception(
         error,
         phone_number,
         attrs,
         body,
         stacktrace
       ) do
    Logger.error("SMS transaction raised exception",
      recipient: phone_number,
      idempotency_key: attrs[:idempotency_key],
      error: inspect(error),
      stacktrace: Exception.format_stacktrace(stacktrace)
    )

    Sentry.capture_exception(error,
      stacktrace: stacktrace,
      extra:
        build_sentry_extra(phone_number, attrs, %{
          message_body: body,
          error_type: inspect(error.__struct__),
          error_message: Exception.message(error)
        }),
      tags: build_sentry_tags(attrs, "sms_transaction_exception")
    )

    emit_send_failed_telemetry(phone_number, attrs, %{error: inspect(error)})

    {:error, "failed to send SMS"}
  end

  defp build_and_run_sms_transaction(phone_number, body, attrs) do
    # attrs already contains phone_number and rendered_message from send_sms_idempotent
    # But we use the parameters here to ensure consistency
    # Merge phone_number and body into attrs for the changeset (matching email pattern)
    idempotency_attrs =
      attrs
      |> Map.put(:phone_number, phone_number)
      |> Map.put(:rendered_message, body)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(
      :message_idempotency,
      MessageIdempotency.changeset(%MessageIdempotency{}, idempotency_attrs)
    )
    |> Ecto.Multi.run(:send_sms, fn _repo, _result ->
      send_sms_via_client(phone_number, body, attrs)
    end)
    |> Repo.transaction()
  end

  defp send_sms_via_client(phone_number, body, attrs) do
    Logger.debug("Sending SMS via FlowRoute Client",
      recipient: phone_number,
      idempotency_key: attrs[:idempotency_key]
    )

    sms_opts = build_sms_opts(phone_number, body, attrs)

    case Client.send_sms(sms_opts) do
      {:ok, %{id: message_id}} = result ->
        Logger.debug("FlowRoute Client.send_sms succeeded",
          recipient: phone_number,
          idempotency_key: attrs[:idempotency_key],
          message_id: message_id
        )

        result

      error ->
        handle_send_sms_error(error, phone_number, attrs, body)
    end
  end

  defp build_sms_opts(phone_number, body, attrs) do
    base_opts = [to: phone_number, body: body]

    if attrs[:from] do
      Keyword.put(base_opts, :from, attrs[:from])
    else
      base_opts
    end
  end

  defp handle_send_sms_error(error, phone_number, attrs, body) do
    Logger.error("FlowRoute Client.send_sms failed",
      recipient: phone_number,
      idempotency_key: attrs[:idempotency_key],
      error: inspect(error)
    )

    Sentry.capture_message("FlowRoute Client.send_sms failed",
      level: :error,
      extra:
        build_sentry_extra(phone_number, attrs, %{
          message_body: body,
          error: inspect(error, limit: :infinity)
        }),
      tags: build_sentry_tags(attrs, "flowroute_send_sms_failed")
    )

    {:error, "failed to send SMS"}
  end

  defp handle_transaction_result(result, phone_number, attrs, _body) do
    case result do
      {:ok,
       %{send_sms: %{id: message_id}, message_idempotency: _message_idempotency}} ->
        handle_successful_sms(phone_number, attrs, message_id)

      {:error, :message_idempotency, changeset, _} ->
        handle_idempotency_duplicate(phone_number, attrs, changeset)

      {:error, operation, reason, _changes} ->
        handle_transaction_error(phone_number, attrs, operation, reason)

      error ->
        handle_unexpected_transaction_error(phone_number, attrs, error)
    end
  end

  defp handle_successful_sms(phone_number, attrs, message_id) do
    Logger.debug("SMS transaction succeeded",
      recipient: phone_number,
      idempotency_key: attrs[:idempotency_key],
      message_id: message_id
    )

    SmsRateLimit.record_sms_send(phone_number)

    :telemetry.execute(
      [:ysc, :sms, :sent],
      %{count: 1},
      build_telemetry_metadata(phone_number, attrs, %{message_id: message_id})
    )

    {:ok, %{id: message_id}}
  end

  defp handle_idempotency_duplicate(phone_number, attrs, changeset) do
    Logger.info("Duplicate SMS detected (idempotency), treating as success",
      recipient: phone_number,
      idempotency_key: attrs[:idempotency_key],
      errors: inspect(changeset.errors)
    )

    :telemetry.execute(
      [:ysc, :sms, :sent],
      %{count: 1},
      build_telemetry_metadata(phone_number, attrs, %{duplicate: true})
    )

    {:ok, %{id: "mdr2-idempotent"}}
  end

  defp handle_transaction_error(phone_number, attrs, operation, reason) do
    Logger.error("SMS transaction failed",
      recipient: phone_number,
      idempotency_key: attrs[:idempotency_key],
      operation: operation,
      reason: inspect(reason)
    )

    Sentry.capture_message("SMS transaction failed",
      level: :error,
      extra:
        build_sentry_extra(phone_number, attrs, %{
          operation: to_string(operation),
          reason: inspect(reason, limit: :infinity)
        }),
      tags:
        build_sentry_tags(attrs, "sms_transaction_failed", %{
          operation: to_string(operation)
        })
    )

    emit_send_failed_telemetry(phone_number, attrs, %{
      operation: to_string(operation),
      reason: inspect(reason)
    })

    {:error, "failed to send SMS"}
  end

  defp handle_unexpected_transaction_error(phone_number, attrs, error) do
    Logger.error("SMS transaction failed with unexpected error",
      recipient: phone_number,
      idempotency_key: attrs[:idempotency_key],
      error: inspect(error)
    )

    Sentry.capture_message("SMS transaction failed with unexpected error",
      level: :error,
      extra:
        build_sentry_extra(phone_number, attrs, %{
          error: inspect(error, limit: :infinity)
        }),
      tags: build_sentry_tags(attrs, "sms_transaction_unexpected_error")
    )

    emit_send_failed_telemetry(phone_number, attrs, %{error: inspect(error)})

    {:error, "failed to send SMS"}
  end

  defp handle_constraint_error(error, phone_number, attrs, body) do
    if error.type == :unique do
      handle_unique_constraint_error(error, phone_number, attrs, body)
    else
      handle_non_unique_constraint_error(error, phone_number, attrs, body)
    end
  end

  defp handle_unique_constraint_error(error, phone_number, attrs, _body) do
    constraint_string = to_string(error.constraint)

    idempotency_constraint_names = [
      "message_idempotency_entries_unique_index",
      "message_idempotency_entries_message_type_idempotency_key_messag"
    ]

    if constraint_string in idempotency_constraint_names do
      handle_idempotency_constraint_duplicate(
        phone_number,
        attrs,
        constraint_string
      )
    else
      handle_non_idempotency_unique_constraint(
        error,
        phone_number,
        attrs,
        constraint_string
      )
    end
  end

  defp handle_idempotency_constraint_duplicate(
         phone_number,
         attrs,
         constraint_string
       ) do
    Logger.info(
      "Duplicate SMS detected (idempotency constraint), treating as success",
      recipient: phone_number,
      idempotency_key: attrs[:idempotency_key],
      constraint: constraint_string
    )

    :telemetry.execute(
      [:ysc, :sms, :sent],
      %{count: 1},
      build_telemetry_metadata(phone_number, attrs, %{duplicate: true})
    )

    {:ok, %{id: "mdr2-idempotent"}}
  end

  defp handle_non_idempotency_unique_constraint(
         error,
         phone_number,
         attrs,
         constraint_string
       ) do
    Logger.error(
      "SMS transaction raised unique constraint error (not idempotency)",
      recipient: phone_number,
      idempotency_key: attrs[:idempotency_key],
      constraint: constraint_string,
      error: inspect(error)
    )

    Sentry.capture_exception(error,
      extra:
        build_sentry_extra(phone_number, attrs, %{
          constraint: constraint_string,
          constraint_type: error.type
        }),
      tags:
        build_sentry_tags(attrs, "unique_constraint_error", %{
          constraint: constraint_string
        })
    )

    emit_send_failed_telemetry(phone_number, attrs, %{
      constraint: constraint_string,
      error: inspect(error)
    })

    {:error, "failed to send SMS"}
  end

  defp handle_non_unique_constraint_error(error, phone_number, attrs, body) do
    Logger.error("SMS transaction raised constraint error (not unique)",
      recipient: phone_number,
      idempotency_key: attrs[:idempotency_key],
      constraint: error.constraint,
      type: error.type,
      error: inspect(error)
    )

    Sentry.capture_exception(error,
      extra:
        build_sentry_extra(phone_number, attrs, %{
          message_body: body,
          constraint: to_string(error.constraint),
          constraint_type: error.type
        }),
      tags:
        build_sentry_tags(attrs, "constraint_error", %{
          constraint: to_string(error.constraint)
        })
    )

    emit_send_failed_telemetry(phone_number, attrs, %{
      constraint: to_string(error.constraint),
      error: inspect(error)
    })

    {:error, "failed to send SMS"}
  end

  defp build_sentry_extra(phone_number, attrs, additional) do
    Map.merge(
      %{
        recipient: phone_number,
        idempotency_key: attrs[:idempotency_key],
        message_template: attrs[:message_template],
        user_id: attrs[:user_id]
      },
      additional
    )
  end

  defp build_sentry_tags(attrs, error_type, additional \\ %{}) do
    Map.merge(
      %{
        sms_template: attrs[:message_template] || "unknown",
        error_type: error_type,
        has_user_id: !is_nil(attrs[:user_id])
      },
      additional
    )
  end

  defp build_telemetry_metadata(phone_number, attrs, additional) do
    Map.merge(
      %{
        template: attrs[:message_template] || "unknown",
        recipient: phone_number,
        idempotency_key: attrs[:idempotency_key] || nil
      },
      additional
    )
  end

  defp emit_send_failed_telemetry(phone_number, attrs, additional) do
    :telemetry.execute(
      [:ysc, :sms, :send_failed],
      %{count: 1},
      build_telemetry_metadata(phone_number, attrs, additional)
    )
  end
end
