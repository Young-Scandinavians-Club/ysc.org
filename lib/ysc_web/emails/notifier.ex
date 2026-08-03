defmodule YscWeb.Emails.Notifier do
  @moduledoc """
  Email notification service.

  Routes email templates to appropriate email modules based on template names.
  """
  import Swoosh.Email

  require Ysc.Logging

  defp from_email do
    Ysc.EmailConfig.from_email()
  end

  defp from_name do
    Ysc.EmailConfig.from_name()
  end

  @template_mappings %{
    "account_setup_verification" => YscWeb.Emails.AccountSetupVerification,
    "application_rejected" => YscWeb.Emails.ApplicationRejected,
    "application_approved" => YscWeb.Emails.ApplicationApproved,
    "application_approved_payment_success" =>
      YscWeb.Emails.ApplicationApprovedPaymentSuccess,
    "application_approved_family_linked" =>
      YscWeb.Emails.ApplicationApprovedFamilyLinked,
    "application_submitted" => YscWeb.Emails.ApplicationSubmitted,
    "reset_password" => YscWeb.Emails.ResetPassword,
    "password_changed" => YscWeb.Emails.PasswordChanged,
    "passkey_added" => YscWeb.Emails.PasskeyAdded,
    "new_sign_in_detected" => YscWeb.Emails.NewSignInDetected,
    "change_email" => YscWeb.Emails.ChangeEmail,
    "email_changed" => YscWeb.Emails.EmailChanged,
    "admin_application_submitted" => YscWeb.Emails.AdminApplicationSubmitted,
    "conduct_violation_confirmation" =>
      YscWeb.Emails.ConductViolationConfirmation,
    "conduct_violation_board_notification" =>
      YscWeb.Emails.ConductViolationBoardNotification,
    "ticket_purchase_confirmation" => YscWeb.Emails.TicketPurchaseConfirmation,
    "ticket_reservation_created" => YscWeb.Emails.TicketReservationCreated,
    "ticket_order_refund" => YscWeb.Emails.TicketOrderRefund,
    "booking_confirmation" => YscWeb.Emails.BookingConfirmation,
    "booking_modification_confirmation" =>
      YscWeb.Emails.BookingModificationConfirmation,
    "booking_entitlement_granted" => YscWeb.Emails.BookingEntitlementGranted,
    "booking_refund_processed" => YscWeb.Emails.BookingRefundProcessed,
    "booking_refund_pending" => YscWeb.Emails.BookingRefundPending,
    "volunteer_confirmation" => YscWeb.Emails.VolunteerConfirmation,
    "volunteer_board_notification" => YscWeb.Emails.VolunteerBoardNotification,
    "contact_form_board_notification" =>
      YscWeb.Emails.ContactFormBoardNotification,
    "outage_notification" => YscWeb.Emails.OutageNotification,
    "membership_payment_failure" => YscWeb.Emails.MembershipPaymentFailure,
    "membership_payment_confirmation" =>
      YscWeb.Emails.MembershipPaymentConfirmation,
    "welcome_email" => YscWeb.Emails.WelcomeEmail,
    "membership_renewal_success" => YscWeb.Emails.MembershipRenewalSuccess,
    "membership_payment_reminder_7day" =>
      YscWeb.Emails.MembershipPaymentReminder7Day,
    "membership_payment_reminder_30day" =>
      YscWeb.Emails.MembershipPaymentReminder30Day,
    "membership_renewal_payment_method_reminder" =>
      YscWeb.Emails.MembershipRenewalPaymentMethodReminder,
    "membership_renewal_reminder" => YscWeb.Emails.MembershipRenewalReminder,
    "family_invite" => YscWeb.Emails.FamilyInvite,
    "family_invite_accepted" => YscWeb.Emails.FamilyInviteAccepted,
    "family_invite_cancelled" => YscWeb.Emails.FamilyInviteCancelled,
    "family_member_removed" => YscWeb.Emails.FamilyMemberRemoved,
    "booking_checkin_reminder" => YscWeb.Emails.BookingCheckinReminder,
    "booking_checkout_reminder" => YscWeb.Emails.BookingCheckoutReminder,
    "event_notification" => YscWeb.Emails.EventNotification,
    "save_the_date_available" => YscWeb.Emails.SaveTheDateAvailable,
    "expense_report_confirmation" => YscWeb.Emails.ExpenseReportConfirmation,
    "expense_report_treasurer_notification" =>
      YscWeb.Emails.ExpenseReportTreasurerNotification,
    "booking_cancellation_cabin_master_notification" =>
      YscWeb.Emails.BookingCancellationCabinMasterNotification,
    "booking_cancellation_treasurer_notification" =>
      YscWeb.Emails.BookingCancellationTreasurerNotification,
    "booking_cancellation_confirmation" =>
      YscWeb.Emails.BookingCancellationConfirmation,
    "event_update_notification" => YscWeb.Emails.EventUpdateNotification,
    "event_photo_upload_reminder" => YscWeb.Emails.EventPhotoUploadReminder,
    "newsletter_stats_snapshot" => YscWeb.Emails.NewsletterStatsSnapshot
  }

  # Legacy call sites pass the configurable reply-to address as the 8th argument (binary).
  # New call sites pass keyword options (reply_to:, cc:, etc.).
  #
  # This standalone enqueue is appropriate for worker-originated fan-out and
  # external events. State mutations must use `schedule_email_multi/3` in
  # their existing Ecto.Multi so the state and Oban job commit together.
  def schedule_email(
        recipient,
        idempotency_key,
        subject,
        template,
        variables,
        text_body,
        user_id,
        reply_to_or_opts \\ []
      )

  def schedule_email(
        recipient,
        idempotency_key,
        subject,
        template,
        variables,
        text_body,
        user_id,
        reply_to
      )
      when is_binary(reply_to) or is_nil(reply_to) do
    schedule_email(
      recipient,
      idempotency_key,
      subject,
      template,
      variables,
      text_body,
      user_id,
      reply_to: reply_to
    )
  end

  def schedule_email(
        recipient,
        idempotency_key,
        subject,
        template,
        variables,
        text_body,
        user_id,
        opts
      )
      when is_list(opts) do
    reply_to_override = Keyword.get(opts, :reply_to)
    cc = Keyword.get(opts, :cc)

    reply_to =
      reply_to_override || Ysc.Accounts.EmailCategories.get_reply_to(template)

    do_schedule_email(
      recipient,
      idempotency_key,
      subject,
      template,
      variables,
      text_body,
      user_id,
      %{reply_to: reply_to, cc: cc}
    )
  end

  def schedule_email(
        recipient,
        idempotency_key,
        subject,
        template,
        variables,
        text_body
      ) do
    schedule_email(
      recipient,
      idempotency_key,
      subject,
      template,
      variables,
      text_body,
      nil,
      []
    )
  end

  @doc """
  Adds an email job to an `Ecto.Multi`.

  The caller must execute the returned multi with the same repository
  transaction as the business mutation that makes the email necessary.

  Pass either a complete attributes map or a function that receives prior
  multi changes and returns that attributes map.
  """
  def schedule_email_multi(multi, operation_name, attrs) when is_map(attrs) do
    Oban.insert(multi, operation_name, email_job_from_attrs(attrs))
  end

  def schedule_email_multi(multi, operation_name, builder)
      when is_function(builder, 1) do
    Oban.insert(multi, operation_name, fn changes ->
      changes |> builder.() |> email_job_from_attrs()
    end)
  end

  defp email_job_from_attrs(attrs) do
    template = Map.fetch!(attrs, :template)
    opts = Map.get(attrs, :opts, [])

    reply_to =
      Keyword.get(opts, :reply_to) ||
        Ysc.Accounts.EmailCategories.get_reply_to(template)

    build_email_job(
      Map.fetch!(attrs, :recipient),
      Map.fetch!(attrs, :idempotency_key),
      Map.fetch!(attrs, :subject),
      template,
      Map.fetch!(attrs, :variables),
      Map.fetch!(attrs, :text_body),
      Map.fetch!(attrs, :user_id),
      %{reply_to: reply_to, cc: Keyword.get(opts, :cc)}
    )
  end

  defp do_schedule_email(
         recipient,
         idempotency_key,
         subject,
         template,
         variables,
         text_body,
         user_id,
         %{reply_to: reply_to, cc: cc}
       ) do
    job =
      build_email_job(
        recipient,
        idempotency_key,
        subject,
        template,
        variables,
        text_body,
        user_id,
        %{reply_to: reply_to, cc: cc}
      )

    case Oban.insert(job) do
      {:ok, %Oban.Job{} = inserted_job} ->
        Ysc.Logging.debug(
          "Notifier.schedule_email: Email job inserted successfully",
          job_id: inserted_job.id,
          recipient: recipient,
          template: template,
          idempotency_key: idempotency_key
        )

        inserted_job

      {:error, reason} = error ->
        Ysc.Logging.error(
          "Notifier.schedule_email: Failed to insert email job - Full error details:\n#{inspect(reason, limit: :infinity)}",
          recipient: recipient,
          template: template,
          idempotency_key: idempotency_key,
          error: inspect(reason, limit: :infinity),
          error_type: determine_error_type(reason)
        )

        error
    end
  end

  defp put_reply_to_job_arg(args, nil), do: args

  defp put_reply_to_job_arg(args, reply_to),
    do: Map.put(args, "reply_to", reply_to)

  defp put_cc_job_arg(args, nil), do: args
  defp put_cc_job_arg(args, ""), do: args
  defp put_cc_job_arg(args, cc) when is_binary(cc), do: Map.put(args, "cc", cc)

  defp build_email_job(
         recipient,
         idempotency_key,
         subject,
         template,
         variables,
         text_body,
         user_id,
         %{reply_to: reply_to, cc: cc}
       ) do
    category = Ysc.Accounts.EmailCategories.get_category(template)

    job_args =
      %{
        "recipient" => recipient,
        "idempotency_key" => idempotency_key,
        "subject" => subject,
        "template" => template,
        "params" => variables,
        "text_body" => text_body,
        "user_id" => user_id,
        "category" => category
      }
      |> put_reply_to_job_arg(reply_to)
      |> put_cc_job_arg(cc)

    YscWeb.Workers.EmailNotifier.new(job_args,
      queue: YscWeb.Workers.EmailNotifier.queue_for_category(category)
    )
  end

  def schedule_email_to_board(
        idempotency_key,
        subject,
        template,
        variables,
        cc \\ nil
      ) do
    board_opts = if(cc, do: [cc: cc], else: [])

    schedule_email(
      from_email(),
      idempotency_key,
      subject,
      template,
      variables,
      "",
      nil,
      board_opts
    )
  end

  @doc """
  Adds a board-notification email job to an `Ecto.Multi`.
  """
  def schedule_email_to_board_multi(
        multi,
        operation_name,
        idempotency_key,
        subject,
        template,
        variables,
        cc \\ nil
      ) do
    board_opts = if(cc, do: [cc: cc], else: [])

    schedule_email_multi(multi, operation_name, %{
      recipient: from_email(),
      idempotency_key: idempotency_key,
      subject: subject,
      template: template,
      variables: variables,
      text_body: "",
      user_id: nil,
      opts: board_opts
    })
  end

  def send_email_idempotent(
        recipient,
        idempotency_key,
        subject,
        template,
        variables,
        text_body,
        user_id,
        opts \\ []
      )
      when is_list(opts) do
    reply_to = Keyword.get(opts, :reply_to)
    cc = Keyword.get(opts, :cc)
    delivery_retry = Keyword.get(opts, :delivery_retry, false)

    rendered = template.render(variables)
    template_name = template.get_template_name()

    attrs = %{
      message_type: :email,
      idempotency_key: idempotency_key,
      message_template: template_name,
      params: variables,
      email: recipient,
      rendered_message: rendered,
      user_id: user_id,
      delivery_retry: delivery_retry
    }

    email =
      new()
      |> to(recipient)
      |> from({from_name(), from_email()})
      |> subject(subject)
      |> maybe_reply_to(reply_to)
      |> add_cc_recipients(cc)
      |> html_body(rendered)
      |> text_body(text_body)

    Ysc.Messages.run_send_message_idempotent(email, attrs)
  end

  defp maybe_reply_to(email, nil), do: email

  defp maybe_reply_to(email, reply_to) when is_binary(reply_to),
    do: reply_to(email, reply_to)

  defp add_cc_recipients(email, nil), do: email
  defp add_cc_recipients(email, ""), do: email

  defp add_cc_recipients(email, cc) when is_binary(cc),
    do: Swoosh.Email.cc(email, cc)

  def send_email_idempotent(
        recipient,
        idempotency_key,
        subject,
        template,
        variables,
        text_body
      ) do
    send_email_idempotent(
      recipient,
      idempotency_key,
      subject,
      template,
      variables,
      text_body,
      nil,
      []
    )
  end

  def send_email_to_board(idempotency_key, subject, template, variables) do
    send_email_idempotent(
      from_email(),
      idempotency_key,
      subject,
      template,
      variables,
      "",
      nil,
      []
    )
  end

  @doc """
  Schedules the membership payment confirmation email.

  Used when a membership payment is recorded (e.g. Stripe webhook or admin-created
  cash-paid membership). Use `paid_elsewhere: true` when the payment was received
  in person (cash, check, etc.) so the email copy reflects that.

  Also schedules the new-member welcome email for 3 days out, for genuinely
  new members only. This function is only ever called for a member's first
  payment — renewals send a separate `membership_renewal_success` email
  instead (see `Ysc.Stripe.WebhookHandler.enqueue_membership_renewal_success_email/6`)
  — so the welcome email is never scheduled for renewals. WP-migrated members
  (`Accounts.wp_migrated?/1`) are also excluded, since they applied and paid
  long before this feature existed and a "getting started" email would be
  irrelevant/confusing for them.
  """
  def deliver_membership_payment_confirmation(
        user,
        membership_type,
        amount,
        payment_date,
        opts \\ []
      ) do
    email_module = YscWeb.Emails.MembershipPaymentConfirmation

    email_data =
      email_module.prepare_email_data(
        user,
        membership_type,
        amount,
        payment_date,
        opts
      )

    subject = email_module.get_subject()
    template_name = email_module.get_template_name()

    payment_date_for_key =
      case payment_date do
        %Date{} = d -> Date.to_iso8601(d)
        %DateTime{} = dt -> DateTime.to_date(dt) |> Date.to_iso8601()
        _ -> Date.utc_today() |> Date.to_iso8601()
      end

    idempotency_key =
      "membership_payment_confirmation_#{user.id}_#{payment_date_for_key}"

    result =
      schedule_email(
        user.email,
        idempotency_key,
        subject,
        template_name,
        email_data,
        "",
        user.id
      )

    if not Ysc.Accounts.wp_migrated?(user) do
      case YscWeb.Workers.WelcomeEmailWorker.schedule_welcome_email(user.id) do
        {:ok, %Oban.Job{}} ->
          :ok

        {:error, reason} ->
          Ysc.Logging.error(
            "Failed to schedule welcome email",
            user_id: user.id,
            error: inspect(reason)
          )
      end
    end

    result
  end

  @doc """
  Sends the new-member welcome email immediately.

  Called from `YscWeb.Workers.WelcomeEmailWorker`, 3 days after
  `deliver_membership_payment_confirmation/5` scheduled it.
  """
  def deliver_welcome_email(user) do
    email_module = YscWeb.Emails.WelcomeEmail
    email_data = email_module.prepare_email_data(user)
    subject = email_module.get_subject()
    template_name = email_module.get_template_name()
    idempotency_key = "welcome_email_#{user.id}"

    schedule_email(
      user.email,
      idempotency_key,
      subject,
      template_name,
      email_data,
      "",
      user.id
    )
  end

  def get_template_module(template_name) do
    @template_mappings[template_name]
  end

  defp determine_error_type(reason) do
    if is_atom(reason) do
      reason
    else
      if is_map(reason) && Map.has_key?(reason, :__struct__) do
        inspect(reason.__struct__)
      else
        :unknown
      end
    end
  end
end
