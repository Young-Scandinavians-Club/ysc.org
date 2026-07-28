defmodule YscWeb.Workers.EmailNotifier do
  @moduledoc """
  Oban worker for sending email notifications.

  Processes email templates and sends them to recipients asynchronously.
  """
  require Ysc.Logging

  use Oban.Worker,
    queue: :transactional_mail,
    max_attempts: 100,
    unique: [
      fields: [:args],
      keys: [:idempotency_key, :template],
      states: :incomplete,
      period: :infinity
    ]

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    template = get_in(job.args, ["template"])
    recipient = get_in(job.args, ["recipient"])

    # Log immediately - this should ALWAYS appear if the function is called
    Ysc.Logging.info("EmailNotifier.perform called - JOB RECEIVED",
      job_id: job.id,
      worker: inspect(job.worker),
      queue: job.queue,
      template: template,
      recipient: recipient,
      state: job.state,
      attempt: job.attempt
    )

    case job.args do
      %{
        "recipient" => recipient,
        "idempotency_key" => idempotency_key,
        "subject" => subject,
        "template" => template,
        "params" => params,
        "text_body" => text_body,
        "user_id" => user_id,
        "category" => category
      } = args ->
        email_params = %{
          job: job,
          recipient: recipient,
          idempotency_key: idempotency_key,
          subject: subject,
          template: template,
          params: params,
          text_body: text_body,
          user_id: user_id,
          category: category,
          reply_to: Map.get(args, "reply_to"),
          cc: Map.get(args, "cc")
        }

        perform_with_args(email_params)

      args ->
        # Try to handle legacy jobs without category
        case args do
          %{
            "recipient" => recipient,
            "idempotency_key" => idempotency_key,
            "subject" => subject,
            "template" => template,
            "params" => params,
            "text_body" => text_body,
            "user_id" => user_id
          } = legacy_args ->
            # Legacy job - get category from template
            category = Ysc.Accounts.EmailCategories.get_category(template)

            email_params = %{
              job: job,
              recipient: recipient,
              idempotency_key: idempotency_key,
              subject: subject,
              template: template,
              params: params,
              text_body: text_body,
              user_id: user_id,
              category: category,
              reply_to: Map.get(legacy_args, "reply_to"),
              cc: Map.get(legacy_args, "cc")
            }

            perform_with_args(email_params)

          _ ->
            Ysc.Logging.error("EmailNotifier job received invalid args",
              job_id: job.id,
              args: args,
              expected_keys: [
                "recipient",
                "idempotency_key",
                "subject",
                "template",
                "params",
                "text_body",
                "user_id",
                "category"
              ]
            )

            {:error, "Invalid job args: missing required fields"}
        end
    end
  end

  @doc false
  def queue_for_category(category)
      when category in [:event, :newsletter, "event", "newsletter"],
      do: :bulk_mail

  def queue_for_category(_category), do: :transactional_mail

  defp perform_with_args(params) do
    Ysc.Logging.debug("EmailNotifier job started",
      job_id: params.job.id,
      recipient: params.recipient,
      idempotency_key: params.idempotency_key,
      subject: params.subject,
      template: params.template,
      user_id: params.user_id,
      category: params.category
    )

    {should_send, final_user_id} =
      check_email_delivery(
        params.user_id,
        params.template,
        params.category,
        params.recipient
      )

    if should_send do
      case Ysc.Messages.ensure_email_delivery(
             delivery_attrs(params, final_user_id)
           ) do
        {:ok, _delivery} ->
          render_and_send(params, final_user_id)

        {:error, reason} ->
          Ysc.Logging.error("Unable to create email delivery record",
            job_id: params.job.id,
            recipient: params.recipient,
            idempotency_key: params.idempotency_key,
            template: params.template,
            error: inspect(reason, limit: :infinity),
            tags: %{error_type: "email_delivery_record_failed"}
          )

          {:error, :delivery_record_failed}
      end
    else
      Ysc.Logging.info("Email notification skipped",
        job_id: params.job.id,
        user_id: params.user_id,
        template: params.template,
        category: params.category
      )

      :ok
    end
  end

  defp render_and_send(params, final_user_id) do
    try do
      template_module =
        YscWeb.Emails.Notifier.get_template_module(params.template)

      if template_module do
        Ysc.Logging.debug("Template module found: #{inspect(template_module)}")
      else
        error_message =
          "Template module not found for template: #{params.template}"

        raise error_message
      end

      case resolve_render_content(
             template_module,
             params.params,
             params.text_body,
             final_user_id
           ) do
        {:ok, {atomized_params, text_body}} ->
          Ysc.Logging.debug("Atomized params: #{inspect(atomized_params)}")

          # Normalize recipient to ensure it's a string (Swoosh can handle tuples/lists, but we want consistency)
          normalized_recipient = normalize_recipient(params.recipient)

          result =
            YscWeb.Emails.Notifier.send_email_idempotent(
              normalized_recipient,
              params.idempotency_key,
              params.subject,
              template_module,
              atomized_params,
              text_body,
              final_user_id,
              email_send_opts(params)
            )

          case result do
            {:ok, _email} ->
              Ysc.Logging.info("Email sent successfully",
                job_id: params.job.id,
                recipient: params.recipient,
                idempotency_key: params.idempotency_key
              )

              :ok

            {:error, {:snooze, seconds}} ->
              Ysc.Logging.info("Email delivery paced by SES limiter",
                job_id: params.job.id,
                recipient: params.recipient,
                retry_after_seconds: seconds
              )

              {:snooze, seconds}

            {:error, {:delivery, delivery_error}} ->
              handle_delivery_error(params, delivery_error)

            {:error, reason} ->
              Ysc.Logging.warning("Failed to send email",
                job_id: params.job.id,
                recipient: params.recipient,
                idempotency_key: params.idempotency_key,
                error: reason
              )

              {:error, reason}
          end

        {:error, reason} ->
          mark_render_failure(params, %{
            code: "render_data_failed",
            message: inspect(reason)
          })
      end
    rescue
      error ->
        mark_render_failure(params, %{
          code: "render_exception",
          message: Exception.message(error),
          exception: inspect(error.__struct__),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        })
    end
  end

  defp delivery_attrs(params, final_user_id) do
    %{
      message_type: :email,
      idempotency_key: params.idempotency_key,
      message_template: params.template,
      params: params.params,
      email: normalize_recipient(params.recipient),
      user_id: final_user_id,
      rendered_message: nil,
      delivery_retry: true
    }
  end

  defp mark_render_failure(params, details) do
    error = %{
      category: :permanent,
      code: details.code,
      message: details.message
    }

    Ysc.Messages.mark_email_terminal(params_to_attrs(params), error)

    Ysc.Logging.error("Email rendering failed; delivery marked terminal",
      job_id: params.job.id,
      recipient: params.recipient,
      idempotency_key: params.idempotency_key,
      template: params.template,
      error_code: details.code,
      error: details.message,
      params_keys: render_param_keys(params.params),
      stacktrace: Map.get(details, :stacktrace),
      tags: %{
        error_type: "email_render_failed",
        email_template: params.template
      }
    )

    {:error, :email_render_failed}
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    # Full jitter prevents a throttled batch from retrying in lockstep.
    cap = min((60 * :math.pow(2, min(attempt, 8))) |> trunc(), 60 * 60)
    :rand.uniform(max(cap, 1))
  end

  defp handle_delivery_error(params, %{category: category} = delivery_error) do
    age_seconds =
      DateTime.diff(DateTime.utc_now(), params.job.inserted_at, :second)

    if category == :permanent or age_seconds >= retry_window_seconds() do
      Ysc.Messages.mark_email_terminal(params_to_attrs(params), delivery_error)

      Ysc.Logging.error("Email delivery reached terminal failure",
        job_id: params.job.id,
        recipient: params.recipient,
        category: category,
        attempts: params.job.attempt,
        age_seconds: age_seconds
      )

      :ok
    else
      Ysc.Logging.warning("Email delivery will retry",
        job_id: params.job.id,
        recipient: params.recipient,
        category: category,
        attempts: params.job.attempt
      )

      {:error, "failed to send email"}
    end
  end

  defp params_to_attrs(params) do
    %{
      message_type: :email,
      idempotency_key: params.idempotency_key,
      message_template: params.template
    }
  end

  defp retry_window_seconds do
    Application.get_env(
      :ysc,
      :email_delivery_retry_window_seconds,
      48 * 60 * 60
    )
  end

  defp render_param_keys(params) when is_map(params),
    do: params |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()

  defp render_param_keys(_params), do: []

  defp resolve_render_content(template_module, job_params, text_body, user_id) do
    if deferred_email_params?(template_module, job_params) do
      if is_nil(user_id) do
        {:error, :missing_user_id}
      else
        user = Ysc.Accounts.get_user!(user_id)
        auth_event_id = Map.get(job_params, "auth_event_id")

        case template_module.prepare_email_data(user, auth_event_id) do
          {:ok, assigns} ->
            body =
              if function_exported?(template_module, :text_body, 1) do
                template_module.text_body(assigns)
              else
                text_body
              end

            {:ok, {assigns, body}}

          {:error, reason} ->
            {:error, reason}
        end
      end
    else
      {:ok, {atomize_keys(job_params), text_body}}
    end
  end

  defp deferred_email_params?(YscWeb.Emails.NewSignInDetected, %{
         "auth_event_id" => auth_event_id
       })
       when is_binary(auth_event_id),
       do: true

  defp deferred_email_params?(_template_module, _job_params), do: false

  def atomize_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      # Use to_existing_atom to prevent atom exhaustion
      # Keys should already be defined atoms in the application
      atom_key =
        try do
          String.to_existing_atom(key)
        rescue
          ArgumentError ->
            # Log warning and keep as string to prevent atom exhaustion
            require Ysc.Logging

            Ysc.Logging.warning(
              "Attempted to atomize unknown key, keeping as string: #{key}"
            )

            key
        end

      {atom_key, atomize_keys(value)}
    end)
  end

  def atomize_keys(list) when is_list(list) do
    Enum.map(list, &atomize_keys/1)
  end

  def atomize_keys(other) do
    other
  end

  defp email_send_opts(params) do
    []
    |> Keyword.put(:delivery_retry, true)
    |> maybe_put_send_opt(:reply_to, params[:reply_to])
    |> maybe_put_send_opt(:cc, params[:cc])
  end

  defp maybe_put_send_opt(kw, _key, nil), do: kw
  defp maybe_put_send_opt(kw, _key, ""), do: kw
  defp maybe_put_send_opt(kw, key, val), do: Keyword.put(kw, key, val)

  # Normalize recipient to a string format
  # Handles cases where recipient might be a list, tuple, or other format
  defp normalize_recipient(recipient) when is_binary(recipient) do
    recipient
  end

  defp normalize_recipient({_name, email}) when is_binary(email) do
    email
  end

  defp normalize_recipient([{_name, email} | _]) when is_binary(email) do
    email
  end

  defp normalize_recipient([email | _]) when is_binary(email) do
    email
  end

  defp normalize_recipient(recipient) do
    # Fallback: use inspect to safely convert any format to string
    # This handles edge cases where recipient might be in an unexpected format
    Ysc.Logging.warning("Unexpected recipient format, normalizing",
      recipient: inspect(recipient),
      recipient_type: recipient_log_type(recipient)
    )

    case recipient do
      list when is_list(list) ->
        case email_from_list(list) do
          nil -> inspect(recipient)
          email -> email
        end

      _ ->
        inspect(recipient)
    end
  end

  defp email_from_list(list) do
    Enum.find_value(list, fn
      {_name, email} when is_binary(email) -> email
      email when is_binary(email) -> email
      _ -> nil
    end)
  end

  defp recipient_log_type(recipient) do
    cond do
      is_list(recipient) ->
        :list

      is_tuple(recipient) ->
        :tuple

      is_map(recipient) and Map.has_key?(recipient, :__struct__) ->
        recipient.__struct__

      is_map(recipient) ->
        :map

      true ->
        :other
    end
  end

  defp check_email_delivery(user_id, template, category, recipient) do
    email = normalize_recipient(recipient)

    if Ysc.Newsletter.hard_bounced?(email) do
      :telemetry.execute(
        [:ysc, :email, :suppressed],
        %{count: 1},
        %{
          reason: :hard_bounce,
          template: template,
          category: category
        }
      )

      Ysc.Logging.info(
        "Email skipped because recipient previously hard bounced",
        user_id: user_id,
        template: template,
        category: category,
        recipient: recipient
      )

      {false, user_id}
    else
      check_user_email_preferences(user_id, template, category, recipient)
    end
  end

  defp check_user_email_preferences(nil, _template, _category, _recipient) do
    # No user_id - send email (e.g., board notifications)
    {true, nil}
  end

  defp check_user_email_preferences(user_id, template, category, recipient) do
    case Ysc.Repo.get(Ysc.Accounts.User, user_id) do
      nil ->
        Ysc.Logging.warning("User not found for email notification",
          user_id: user_id,
          template: template
        )

        {true, nil}

      user ->
        should_send =
          Ysc.Accounts.EmailCategories.should_send_email?(user, template)

        if should_send do
          {true, user_id}
        else
          Ysc.Logging.info("Email skipped due to user notification preferences",
            user_id: user_id,
            template: template,
            category: category,
            recipient: recipient
          )

          {false, user_id}
        end
    end
  end
end
