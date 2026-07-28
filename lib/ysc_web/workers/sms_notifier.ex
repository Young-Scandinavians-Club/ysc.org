defmodule YscWeb.Workers.SmsNotifier do
  @moduledoc """
  Oban worker for sending SMS notifications.

  Processes SMS templates and sends them to recipients asynchronously.
  """
  require Ysc.Logging

  use Oban.Worker,
    queue: :sms,
    max_attempts: 3,
    unique: [
      fields: [:args],
      keys: [:idempotency_key, :template],
      states: :incomplete,
      period: :infinity
    ]

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    template = get_in(job.args, ["template"])
    phone_number = get_in(job.args, ["phone_number"])

    # Log immediately - this should ALWAYS appear if the function is called
    Ysc.Logging.info("SmsNotifier.perform called - JOB RECEIVED",
      job_id: job.id,
      worker: inspect(job.worker),
      queue: job.queue,
      template: template,
      phone_number: phone_number,
      state: job.state,
      attempt: job.attempt
    )

    case job.args do
      %{
        "phone_number" => phone_number,
        "idempotency_key" => idempotency_key,
        "template" => template,
        "params" => params,
        "user_id" => user_id,
        "category" => category
      } ->
        perform_with_args(
          job,
          phone_number,
          idempotency_key,
          template,
          params,
          user_id,
          category
        )

      args ->
        # Try to handle legacy jobs without category
        case args do
          %{
            "phone_number" => phone_number,
            "idempotency_key" => idempotency_key,
            "template" => template,
            "params" => params,
            "user_id" => user_id
          } ->
            # Legacy job - get category from template
            category = Ysc.Accounts.SmsCategories.get_category(template)

            perform_with_args(
              job,
              phone_number,
              idempotency_key,
              template,
              params,
              user_id,
              category
            )

          _ ->
            Ysc.Logging.warning("SmsNotifier job received invalid args",
              job_id: job.id,
              args: args,
              expected_keys: [
                "phone_number",
                "idempotency_key",
                "template",
                "params",
                "user_id",
                "category"
              ]
            )

            {:error, "Invalid job args: missing required fields"}
        end
    end
  end

  defp perform_with_args(
         job,
         phone_number,
         idempotency_key,
         template,
         params,
         user_id,
         category
       ) do
    log_perform_with_args_start(
      job,
      phone_number,
      params,
      idempotency_key,
      template,
      user_id,
      category
    )

    if user_id do
      handle_sms_with_user(
        job,
        phone_number,
        idempotency_key,
        template,
        params,
        user_id,
        category
      )
    else
      send_sms(
        job,
        phone_number,
        idempotency_key,
        template,
        params,
        user_id,
        category
      )
    end
  end

  defp log_perform_with_args_start(
         job,
         phone_number,
         params,
         idempotency_key,
         template,
         user_id,
         category
       ) do
    phone_number_type = get_type_string(phone_number)
    params_type = get_type_string(params)

    Ysc.Logging.debug("SmsNotifier.perform_with_args called",
      job_id: job.id,
      phone_number: phone_number,
      phone_number_type: phone_number_type,
      phone_number_inspect: inspect(phone_number),
      idempotency_key: idempotency_key,
      template: template,
      params: inspect(params, limit: :infinity),
      params_type: params_type,
      user_id: user_id,
      category: category
    )
  end

  defp handle_sms_with_user(
         job,
         phone_number,
         idempotency_key,
         template,
         params,
         user_id,
         category
       ) do
    case Ysc.Accounts.get_user(user_id) do
      nil ->
        Ysc.Logging.warning("SMS sent without user validation - user not found",
          job_id: job.id,
          user_id: user_id,
          template: template
        )

        send_sms(
          job,
          phone_number,
          idempotency_key,
          template,
          params,
          user_id,
          category
        )

      user ->
        handle_sms_for_user(
          job,
          phone_number,
          idempotency_key,
          template,
          params,
          user_id,
          category,
          user
        )
    end
  end

  defp handle_sms_for_user(
         job,
         phone_number,
         idempotency_key,
         template,
         params,
         user_id,
         category,
         user
       ) do
    # Validate template first before checking user preferences
    template_module = YscWeb.Sms.Notifier.get_template_module(template)

    if is_nil(template_module) do
      error_message = "Template module not found for template: #{template}"
      Ysc.Logging.warning("Template module not found for template: #{template}")
      {:error, error_message}
    else
      if Ysc.Accounts.SmsCategories.should_send_sms?(user, template) do
        handle_sms_with_phone_check(
          job,
          phone_number,
          idempotency_key,
          template,
          params,
          user_id,
          category,
          user
        )
      else
        Ysc.Logging.info("SMS not sent - user has disabled notifications",
          job_id: job.id,
          user_id: user_id,
          template: template,
          category: category
        )

        :ok
      end
    end
  end

  defp handle_sms_with_phone_check(
         job,
         phone_number,
         idempotency_key,
         template,
         params,
         user_id,
         category,
         user
       ) do
    if Ysc.Accounts.SmsCategories.has_phone_number?(user) do
      final_phone_number = phone_number || user.phone_number

      log_phone_number_selection(
        job,
        phone_number,
        user.phone_number,
        final_phone_number
      )

      send_sms(
        job,
        final_phone_number,
        idempotency_key,
        template,
        params,
        user_id,
        category
      )
    else
      Ysc.Logging.info("SMS not sent - user has no phone number",
        job_id: job.id,
        user_id: user_id,
        template: template
      )

      :ok
    end
  end

  defp log_phone_number_selection(
         job,
         provided_phone_number,
         user_phone_number,
         final_phone_number
       ) do
    final_phone_number_type = get_phone_number_type_string(final_phone_number)

    Ysc.Logging.debug("Using final phone number for SMS",
      job_id: job.id,
      provided_phone_number: provided_phone_number,
      user_phone_number: user_phone_number,
      final_phone_number: final_phone_number,
      final_phone_number_type: final_phone_number_type
    )
  end

  defp get_type_string(value) do
    if is_struct(value), do: inspect(value.__struct__), else: "not_struct"
  end

  defp get_phone_number_type_string(phone_number) do
    if is_binary(phone_number) do
      "binary"
    else
      if is_struct(phone_number) do
        inspect(phone_number.__struct__)
      else
        "unknown"
      end
    end
  end

  defp send_sms(
         job,
         phone_number,
         idempotency_key,
         template,
         params,
         user_id,
         category
       ) do
    log_send_sms_start(
      job,
      phone_number,
      params,
      idempotency_key,
      template,
      user_id,
      category
    )

    atomized_params = prepare_and_atomize_params(job, params)

    send_sms_and_handle_result(
      job,
      phone_number,
      idempotency_key,
      template,
      atomized_params,
      user_id,
      category
    )
  end

  defp log_send_sms_start(
         job,
         phone_number,
         params,
         idempotency_key,
         template,
         user_id,
         category
       ) do
    phone_number_type = get_phone_number_type_string(phone_number)
    params_type = get_params_type_string(params)

    Ysc.Logging.debug("SmsNotifier.send_sms called",
      job_id: job.id,
      phone_number: phone_number,
      phone_number_type: phone_number_type,
      phone_number_inspect: inspect(phone_number),
      idempotency_key: idempotency_key,
      template: template,
      params_raw: inspect(params, limit: :infinity),
      params_type: params_type,
      user_id: user_id,
      category: category
    )
  end

  defp get_params_type_string(params)
       when is_map(params) and not is_struct(params), do: "map"

  defp get_params_type_string(params) when is_struct(params),
    do: inspect(params.__struct__)

  defp get_params_type_string(_), do: "unknown"

  defp prepare_and_atomize_params(job, params) do
    params_type_before = get_params_type_string(params)

    Ysc.Logging.debug("About to atomize params",
      job_id: job.id,
      params_before: inspect(params, limit: :infinity),
      params_type: params_type_before
    )

    atomized_params = atomize_keys(params)

    atomized_params_type = get_params_type_string(atomized_params)

    Ysc.Logging.debug("Atomized params completed",
      job_id: job.id,
      atomized_params: inspect(atomized_params, limit: :infinity),
      atomized_params_type: atomized_params_type
    )

    atomized_params
  end

  defp send_sms_and_handle_result(
         job,
         phone_number,
         idempotency_key,
         template,
         atomized_params,
         user_id,
         category
       ) do
    phone_number_type_before_call = get_phone_number_type_string(phone_number)

    Ysc.Logging.debug("About to call send_sms_idempotent",
      job_id: job.id,
      phone_number: phone_number,
      phone_number_type: phone_number_type_before_call,
      idempotency_key: idempotency_key,
      template: template,
      atomized_params: inspect(atomized_params, limit: :infinity),
      user_id: user_id
    )

    result =
      YscWeb.Sms.Notifier.send_sms_idempotent(
        phone_number,
        idempotency_key,
        template,
        atomized_params,
        user_id
      )

    Ysc.Logging.debug("send_sms_idempotent returned",
      job_id: job.id,
      result: inspect(result, limit: :infinity)
    )

    handle_sms_result(
      result,
      job,
      phone_number,
      idempotency_key,
      template,
      user_id,
      category
    )
  end

  @dialyzer {:nowarn_function, handle_sms_result: 7}
  defp handle_sms_result(
         {:ok, %{id: message_id}},
         job,
         phone_number,
         idempotency_key,
         template,
         _user_id,
         _category
       ) do
    Ysc.Logging.info("SMS sent successfully",
      job_id: job.id,
      phone_number: phone_number,
      template: template,
      message_id: message_id,
      idempotency_key: idempotency_key
    )

    :ok
  end

  defp handle_sms_result(
         {:error, reason},
         job,
         phone_number,
         idempotency_key,
         template,
         _user_id,
         _category
       ) do
    Ysc.Logging.error("Failed to send SMS",
      job_id: job.id,
      phone_number: phone_number,
      template: template,
      idempotency_key: idempotency_key,
      reason: inspect(reason)
    )

    {:error, reason}
  end

  # Helper function to convert string keys to atoms
  defp atomize_keys(params) when is_map(params) do
    Enum.reduce(params, %{}, fn {key, value}, acc ->
      if is_binary(key) do
        try do
          atom_key = String.to_existing_atom(key)
          Map.put(acc, atom_key, atomize_keys(value))
        rescue
          ArgumentError ->
            key_type = "not_struct"

            Ysc.Logging.error(
              "Failed to convert key to existing atom in atomize_keys",
              key: key,
              key_type: key_type,
              value: inspect(value, limit: 100),
              current_map: inspect(params, limit: :infinity)
            )

            reraise ArgumentError,
                    [message: "Key '#{key}' does not exist as an atom"],
                    __STACKTRACE__
        end
      else
        Map.put(acc, key, atomize_keys(value))
      end
    end)
  end

  defp atomize_keys(value) when is_list(value) do
    Ysc.Logging.debug("Atomizing list value",
      list_length: length(value),
      list_preview: inspect(value, limit: 5)
    )

    Enum.map(value, &atomize_keys/1)
  end

  defp atomize_keys(value) do
    Ysc.Logging.debug("Atomizing non-map, non-list value",
      value_preview: inspect(value, limit: 100)
    )

    value
  end
end
