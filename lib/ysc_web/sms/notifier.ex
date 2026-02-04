defmodule YscWeb.Sms.Notifier do
  @moduledoc """
  SMS notification service.

  Routes SMS templates to appropriate SMS modules based on template names.
  Handles user preference checking and phone number validation.
  """

  require Logger

  @template_mappings %{
    "booking_checkin_reminder" => YscWeb.Sms.BookingCheckinReminder,
    "two_factor_verification" => YscWeb.Sms.TwoFactorVerification,
    "email_changed" => YscWeb.Sms.EmailChanged,
    "password_changed" => YscWeb.Sms.PasswordChanged,
    "phone_verification" => YscWeb.Sms.PhoneVerification
  }

  @doc """
  Schedules an SMS to be sent via Oban worker.

  Checks user preferences and phone number before scheduling.
  """
  @spec schedule_sms(
          String.t(),
          String.t(),
          String.t(),
          map(),
          String.t() | nil
        ) ::
          {:ok, Oban.Job.t()} | {:error, atom()}
  def schedule_sms(
        phone_number,
        idempotency_key,
        template,
        variables,
        user_id \\ nil
      ) do
    # Get category for this template
    category = Ysc.Accounts.SmsCategories.get_category(template)

    # Check user preferences and validate phone number
    case validate_and_get_phone_number(
           phone_number,
           template,
           user_id,
           category
         ) do
      {:ok, validated_phone_number} ->
        # Oban jobs require string keys in args
        job =
          %{
            "phone_number" => validated_phone_number,
            "idempotency_key" => idempotency_key,
            "template" => template,
            "params" => variables,
            "user_id" => user_id,
            "category" => category
          }
          |> YscWeb.Workers.SmsNotifier.new()

        case Oban.insert(job) do
          {:ok, %Oban.Job{} = inserted_job} ->
            Logger.debug(
              "Sms.Notifier.schedule_sms: SMS job inserted successfully",
              job_id: inserted_job.id,
              phone_number: validated_phone_number,
              template: template,
              idempotency_key: idempotency_key
            )

            {:ok, inserted_job}

          {:error, reason} = error ->
            Logger.error("Sms.Notifier.schedule_sms: Failed to insert SMS job",
              phone_number: validated_phone_number,
              template: template,
              idempotency_key: idempotency_key,
              error: inspect(reason, limit: :infinity)
            )

            Sentry.capture_message("Failed to insert SMS job",
              level: :error,
              extra: %{
                phone_number: validated_phone_number,
                template: template,
                idempotency_key: idempotency_key,
                user_id: user_id,
                category: category,
                error: inspect(reason, limit: :infinity)
              },
              tags: %{
                sms_template: template,
                sms_category: to_string(category),
                error_type: "oban_insert_failed",
                has_user_id: !is_nil(user_id)
              }
            )

            error
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp validate_and_get_phone_number(phone_number, template, user_id, category) do
    Logger.debug("validate_and_get_phone_number called",
      phone_number: phone_number,
      phone_number_type:
        if(is_binary(phone_number),
          do: "binary",
          else:
            if(is_struct(phone_number),
              do: inspect(phone_number.__struct__),
              else: "unknown"
            )
        ),
      phone_number_inspect: inspect(phone_number),
      template: template,
      user_id: user_id,
      category: category
    )

    # Check user preferences if user_id is provided
    if user_id do
      case Ysc.Accounts.get_user(user_id) do
        nil ->
          Logger.warning(
            "SMS scheduled without user validation - user not found",
            user_id: user_id,
            template: template
          )

          # Validate phone number format even if user not found
          normalized = normalize_phone_number(phone_number)
          is_valid = valid_phone_number?(phone_number)

          Logger.debug("Phone number validation (user not found)",
            phone_number: phone_number,
            normalized: normalized,
            is_valid: is_valid
          )

          if is_valid do
            {:ok, normalized}
          else
            Logger.warning("SMS not scheduled - invalid phone number format",
              phone_number: phone_number,
              normalized: normalized,
              template: template
            )

            {:error, :invalid_phone_number}
          end

        user ->
          if Ysc.Accounts.SmsCategories.should_send_sms?(user, template) do
            if Ysc.Accounts.SmsCategories.has_phone_number?(user) do
              # Use user's phone number if not provided
              validated_phone = phone_number || user.phone_number
              normalized = normalize_phone_number(validated_phone)
              is_valid = valid_phone_number?(validated_phone)

              Logger.debug("Phone number validation (with user)",
                provided_phone_number: phone_number,
                user_phone_number: user.phone_number,
                validated_phone: validated_phone,
                normalized: normalized,
                is_valid: is_valid
              )

              if is_valid do
                {:ok, normalized}
              else
                Logger.warning(
                  "SMS not scheduled - invalid phone number format",
                  phone_number: validated_phone,
                  normalized: normalized,
                  template: template
                )

                {:error, :invalid_phone_number}
              end
            else
              Logger.info("SMS not scheduled - user has no phone number",
                user_id: user_id,
                template: template
              )

              {:error, :no_phone_number}
            end
          else
            Logger.info("SMS not scheduled - user has disabled notifications",
              user_id: user_id,
              template: template,
              category: category
            )

            {:error, :notifications_disabled}
          end
      end
    else
      # Validate phone number format when no user_id
      normalized = normalize_phone_number(phone_number)
      is_valid = valid_phone_number?(phone_number)

      Logger.debug("Phone number validation (no user_id)",
        phone_number: phone_number,
        normalized: normalized,
        is_valid: is_valid
      )

      if is_valid do
        {:ok, normalized}
      else
        Logger.warning("SMS not scheduled - invalid phone number format",
          phone_number: phone_number,
          normalized: normalized,
          template: template
        )

        {:error, :invalid_phone_number}
      end
    end
  end

  @doc """
  Sends an SMS immediately with idempotency handling.

  Checks user preferences and phone number before sending.
  """
  @spec send_sms_idempotent(
          String.t(),
          String.t(),
          String.t(),
          map(),
          String.t() | nil
        ) ::
          {:ok, map()} | {:error, String.t()}
  def send_sms_idempotent(
        phone_number,
        idempotency_key,
        template,
        variables,
        user_id \\ nil
      ) do
    # Get template module
    template_module = get_template_module(template)

    if is_nil(template_module) do
      error_message = "Template module not found for template: #{template}"

      Logger.warning(error_message)

      {:error, error_message}
    else
      # Check user preferences and validate phone number
      case validate_and_get_phone_number(phone_number, template, user_id, nil) do
        {:ok, validated_phone_number} ->
          # Render SMS message
          body = template_module.render(variables)
          template_name = template_module.get_template_name()

          attrs = %{
            message_type: :sms,
            idempotency_key: idempotency_key,
            message_template: template_name,
            params: variables,
            phone_number: validated_phone_number,
            rendered_message: body,
            user_id: user_id
          }

          Ysc.Messages.run_send_sms_idempotent(
            validated_phone_number,
            body,
            attrs
          )

        {:error, _reason} = error ->
          error
      end
    end
  end

  @doc """
  Gets the template module for a given template name.
  """
  @spec get_template_module(String.t()) :: module() | nil
  def get_template_module(template_name) do
    @template_mappings[template_name]
  end

  # Private functions

  defp valid_phone_number?(phone_number) when is_binary(phone_number) do
    # Normalize phone number (remove + prefix if present) and validate
    normalized = normalize_phone_number(phone_number)
    # Validate 11-digit North American format (e.g., 12065551234)
    # Also ensure normalized string is not empty
    is_valid = normalized != "" && Regex.match?(~r/^1\d{10}$/, normalized)

    Logger.debug("valid_phone_number? check",
      original: phone_number,
      normalized: normalized,
      is_valid: is_valid,
      normalized_length: String.length(normalized)
    )

    is_valid
  end

  defp valid_phone_number?(_), do: false

  # Normalizes phone number to format expected by SMS provider (1XXXXXXXXXX)
  # Removes + prefix and any non-digit characters
  defp normalize_phone_number(phone_number) when is_binary(phone_number) do
    normalized =
      phone_number
      # Remove leading +
      |> String.replace(~r/^\+/, "")
      # Remove all non-digit characters
      |> String.replace(~r/[^\d]/, "")

    Logger.debug("normalize_phone_number",
      original: phone_number,
      normalized: normalized,
      original_length: String.length(phone_number),
      normalized_length: String.length(normalized)
    )

    normalized
  end

  defp normalize_phone_number(nil), do: ""
  defp normalize_phone_number(_), do: ""
end
