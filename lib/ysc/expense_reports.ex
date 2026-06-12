defmodule Ysc.ExpenseReports do
  @moduledoc """
  Context module for managing expense reports.
  """
  require Ysc.Logging
  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.Accounts.{Address, User}

  alias Ysc.ExpenseReports.{
    ExpenseReport,
    ExpenseReportItem,
    ExpenseReportIncomeItem,
    BankAccount
  }

  alias Ysc.S3Config

  alias YscWeb.Emails.{
    Notifier,
    ExpenseReportConfirmation,
    ExpenseReportTreasurerNotification
  }

  # Expense Reports

  def list_expense_reports(%User{} = user) do
    user.id
    |> expense_reports_query()
    |> Repo.all()
    |> attach_bank_accounts()
  end

  def get_expense_report!(id, %User{} = user) do
    user.id
    |> expense_reports_query()
    |> where([er], er.id == ^id)
    |> Repo.one!()
    |> List.wrap()
    |> attach_bank_accounts()
    |> List.first()
  end

  defp expense_reports_query(user_id) do
    from er in ExpenseReport,
      where: er.user_id == ^user_id,
      order_by: [desc: :inserted_at],
      preload: [:expense_items, :income_items, :address, :event]
  end

  # Bank accounts are loaded in a second query so encrypted fields are not
  # pulled via join/preload; batch by id to avoid N+1 on list endpoints.
  defp attach_bank_accounts(reports) when is_list(reports) do
    bank_account_ids =
      reports
      |> Enum.map(& &1.bank_account_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    accounts_by_id =
      if bank_account_ids == [] do
        %{}
      else
        from(ba in BankAccount, where: ba.id in ^bank_account_ids)
        |> Repo.all()
        |> Map.new(&{&1.id, &1})
      end

    Enum.map(reports, fn report ->
      bank_account =
        if report.bank_account_id do
          Map.get(accounts_by_id, report.bank_account_id)
        end

      %{report | bank_account: bank_account}
    end)
  end

  def create_expense_report(attrs, %User{} = user) do
    require Ysc.Logging

    # Set status to "submitted" if not already set (for submissions)
    attrs = Map.put_new(attrs, "status", "submitted")

    changeset =
      %ExpenseReport{}
      |> ExpenseReport.submission_changeset(Map.put(attrs, "user_id", user.id))
      |> validate_reimbursement_setup(user)
      |> validate_reimbursement_ownership(user)
      |> validate_all_expense_items_have_receipts_for_submission()

    Ysc.Logging.debug(
      "Expense report changeset - valid?: #{changeset.valid?}, errors: #{inspect(changeset.errors, limit: 20)}"
    )

    # Check for nested association errors
    expense_items = Ecto.Changeset.get_field(changeset, :expense_items, [])
    Ysc.Logging.debug("Expense items count: #{length(expense_items)}")

    Enum.with_index(expense_items)
    |> Enum.each(fn {item, idx} ->
      case item do
        %Ecto.Changeset{} = cs ->
          receipt_path = Ecto.Changeset.get_field(cs, :receipt_s3_path)

          Ysc.Logging.debug(
            "Expense item #{idx} - valid?: #{cs.valid?}, errors: #{inspect(cs.errors, limit: 10)}, receipt: #{inspect(receipt_path)}"
          )

        struct ->
          receipt_path = Map.get(struct, :receipt_s3_path)

          Ysc.Logging.debug(
            "Expense item #{idx} - struct, receipt: #{inspect(receipt_path)}"
          )
      end
    end)

    # Also check if there are changeset errors in the associations
    if Map.has_key?(changeset.changes, :expense_items) do
      Ysc.Logging.debug("expense_items in changes - checking for errors")

      case changeset.changes[:expense_items] do
        list when is_list(list) ->
          Enum.with_index(list)
          |> Enum.each(fn {item, idx} ->
            case item do
              %Ecto.Changeset{} = cs ->
                Ysc.Logging.debug(
                  "Changed expense item #{idx} - valid?: #{cs.valid?}, errors: #{inspect(cs.errors, limit: 10)}"
                )

              _ ->
                :ok
            end
          end)

        _ ->
          :ok
      end
    end

    result = Repo.insert(changeset)

    # Enqueue QuickBooks sync job and send emails if expense report was created with "submitted" status
    case result do
      {:ok, expense_report} ->
        if expense_report.status == "submitted" do
          Ysc.Logging.debug(
            "Expense report created with submitted status, enqueueing QuickBooks sync",
            expense_report_id: expense_report.id
          )

          enqueue_quickbooks_sync(expense_report)
          send_expense_report_emails(expense_report)
        else
          Ysc.Logging.debug(
            "Expense report created with status: #{expense_report.status}, skipping QuickBooks sync and emails",
            expense_report_id: expense_report.id
          )
        end

        result

      error ->
        error
    end
  end

  defp validate_all_expense_items_have_receipts_for_submission(changeset) do
    # Only validate if status is "submitted"
    status = Ecto.Changeset.get_field(changeset, :status)

    if status == "submitted" do
      expense_items = Ecto.Changeset.get_field(changeset, :expense_items, [])

      items_without_receipts =
        expense_items
        |> Enum.filter(fn item ->
          receipt_path = get_receipt_path_from_item(item)
          is_nil(receipt_path) || receipt_path == ""
        end)

      if Enum.any?(items_without_receipts) do
        Ecto.Changeset.add_error(
          changeset,
          :expense_items,
          "All expense items must have a receipt attached before submission"
        )
      else
        changeset
      end
    else
      changeset
    end
  end

  defp get_receipt_path_from_item(%Ecto.Changeset{} = item) do
    Ecto.Changeset.get_field(item, :receipt_s3_path)
  end

  defp get_receipt_path_from_item(%ExpenseReportItem{} = item) do
    item.receipt_s3_path
  end

  defp get_receipt_path_from_item(_), do: nil

  defp validate_reimbursement_setup(changeset, %User{} = user) do
    method = Ecto.Changeset.get_field(changeset, :reimbursement_method)

    case method do
      "bank_transfer" ->
        bank_account_id = Ecto.Changeset.get_field(changeset, :bank_account_id)

        if is_nil(bank_account_id) do
          # Check if user has any bank accounts
          bank_accounts = list_bank_accounts(user)

          if bank_accounts == [] do
            Ecto.Changeset.add_error(
              changeset,
              :reimbursement_method,
              "requires a bank account. Please add a bank account in your user settings before submitting."
            )
          else
            Ecto.Changeset.add_error(
              changeset,
              :bank_account_id,
              "must be selected. Please choose a bank account above."
            )
          end
        else
          changeset
        end

      "check" ->
        validate_check_reimbursement_method(changeset, user)

      _ ->
        changeset
    end
  end

  defp validate_reimbursement_ownership(changeset, %User{} = user) do
    changeset
    |> validate_bank_account_owned_by_user(user)
    |> validate_address_owned_by_user(user)
  end

  defp validate_bank_account_owned_by_user(changeset, %User{} = user) do
    case Ecto.Changeset.get_field(changeset, :bank_account_id) do
      nil ->
        changeset

      bank_account_id ->
        if Repo.exists?(
             from ba in BankAccount,
               where: ba.id == ^bank_account_id and ba.user_id == ^user.id
           ) do
          changeset
        else
          Ecto.Changeset.add_error(changeset, :bank_account_id, "is invalid")
        end
    end
  end

  defp validate_address_owned_by_user(changeset, %User{} = user) do
    case Ecto.Changeset.get_field(changeset, :address_id) do
      nil ->
        changeset

      address_id ->
        if Repo.exists?(
             from a in Address,
               where: a.id == ^address_id and a.user_id == ^user.id
           ) do
          changeset
        else
          Ecto.Changeset.add_error(changeset, :address_id, "is invalid")
        end
    end
  end

  def update_expense_report(%ExpenseReport{} = expense_report, attrs) do
    expense_report
    |> ExpenseReport.status_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Marks an expense report as paid.

  This is called when a payment is initiated in QuickBooks (via webhook).
  """
  def mark_expense_report_as_paid(%ExpenseReport{} = expense_report) do
    expense_report
    |> ExpenseReport.changeset(%{status: "paid"})
    |> Repo.update()
  end

  def submit_expense_report(%ExpenseReport{} = expense_report) do
    result =
      expense_report
      |> ExpenseReport.changeset(%{status: "submitted"})
      |> Repo.update()

    # Enqueue QuickBooks sync job if submission was successful
    case result do
      {:ok, updated_report} ->
        enqueue_quickbooks_sync(updated_report)
        result

      error ->
        error
    end
  end

  defp enqueue_quickbooks_sync(%ExpenseReport{} = expense_report) do
    Ysc.Logging.debug("Starting enqueue_quickbooks_sync",
      expense_report_id: expense_report.id,
      current_status: expense_report.quickbooks_sync_status
    )

    # Mark as pending sync
    update_result =
      expense_report
      |> ExpenseReport.changeset(%{quickbooks_sync_status: "pending"})
      |> Repo.update()

    case update_result do
      {:ok, updated_report} ->
        Ysc.Logging.debug("Marked expense report as pending sync",
          expense_report_id: updated_report.id
        )

        # Enqueue Oban job
        job_result =
          %{"expense_report_id" => expense_report.id}
          |> YscWeb.Workers.QuickbooksSyncExpenseReportWorker.new()
          |> Oban.insert()

        case job_result do
          {:ok, job} ->
            Ysc.Logging.info("Enqueued QuickBooks sync for expense report",
              expense_report_id: expense_report.id,
              job_id: job.id,
              queue: job.queue,
              scheduled_at: job.scheduled_at
            )

          {:error, reason} ->
            Ysc.Logging.error(
              "Failed to enqueue QuickBooks sync for expense report",
              expense_report_id: expense_report.id,
              error: inspect(reason),
              extra: %{
                expense_report_id: expense_report.id,
                error: inspect(reason)
              },
              tags: %{
                quickbooks_operation: "enqueue_expense_report_sync"
              }
            )
        end

      {:error, changeset} ->
        Ysc.Logging.error("Failed to mark expense report as pending sync",
          expense_report_id: expense_report.id,
          errors: inspect(changeset.errors)
        )
    end
  end

  defp send_expense_report_emails(%ExpenseReport{} = expense_report) do
    require Ysc.Logging

    # Ensure expense report has an ID (must be saved to database)
    if is_nil(expense_report.id) do
      Ysc.Logging.warning("Cannot send emails for expense report without ID",
        expense_report: inspect(expense_report, limit: 100)
      )

      :ok
    else
      # Reload expense report with all necessary associations for email
      # This ensures we have fresh data from the database
      case Repo.get(ExpenseReport, expense_report.id)
           |> Repo.preload([
             :user,
             :expense_items,
             :income_items,
             :event,
             :bank_account,
             :address
           ]) do
        nil ->
          Ysc.Logging.error(
            "Expense report not found in database when sending emails",
            expense_report_id: expense_report.id
          )

          :ok

        loaded_report ->
          validate_and_send_expense_report_emails(loaded_report)
      end
    end
  end

  @dialyzer {:nowarn_function, send_expense_report_emails_impl: 1}
  defp send_expense_report_emails_impl(%ExpenseReport{} = expense_report) do
    require Ysc.Logging

    Ysc.Logging.info("send_expense_report_emails_impl: Starting email sending",
      expense_report_id: expense_report.id,
      user_id: expense_report.user_id,
      user_loaded: Ecto.assoc_loaded?(expense_report.user),
      expense_items_count:
        if(Ecto.assoc_loaded?(expense_report.expense_items),
          do: length(expense_report.expense_items),
          else: :not_loaded
        ),
      income_items_count:
        if(Ecto.assoc_loaded?(expense_report.income_items),
          do: length(expense_report.income_items),
          else: :not_loaded
        )
    )

    # Send confirmation email to user
    try do
      Ysc.Logging.info(
        "send_expense_report_emails_impl: Preparing confirmation email data",
        expense_report_id: expense_report.id,
        user_email:
          if(expense_report.user, do: expense_report.user.email, else: nil)
      )

      email_data = ExpenseReportConfirmation.prepare_email_data(expense_report)

      Ysc.Logging.info("send_expense_report_emails_impl: Email data prepared",
        expense_report_id: expense_report.id,
        email_data_keys: Map.keys(email_data),
        email_data_expense_report_keys: Map.keys(email_data.expense_report),
        email_data_first_name: Map.get(email_data, :first_name),
        expense_items_count: length(email_data.expense_report.expense_items)
      )

      subject = ExpenseReportConfirmation.get_subject()
      idempotency_key = "expense_report_confirmation_#{expense_report.id}"

      template_name = ExpenseReportConfirmation.get_template_name()

      Ysc.Logging.info(
        "send_expense_report_emails_impl: Calling Notifier.schedule_email",
        expense_report_id: expense_report.id,
        recipient: expense_report.user.email,
        subject: subject,
        idempotency_key: idempotency_key,
        template_name: template_name,
        template_module: inspect(ExpenseReportConfirmation),
        user_id: expense_report.user.id,
        email_data_type: inspect(email_data, limit: 200),
        email_data_keys: Map.keys(email_data)
      )

      result =
        Notifier.schedule_email(
          expense_report.user.email,
          idempotency_key,
          subject,
          template_name,
          email_data,
          "",
          expense_report.user.id
        )

      case result do
        {:error, _reason} ->
          Ysc.Logging.warning(
            "Failed to schedule expense report confirmation email",
            expense_report_id: expense_report.id,
            recipient: expense_report.user.email,
            result: inspect(result, limit: 100)
          )

        _ ->
          Ysc.Logging.debug("Scheduled expense report confirmation email",
            expense_report_id: expense_report.id,
            recipient: expense_report.user.email
          )
      end
    rescue
      e ->
        exception_type = e.__struct__
        exception_message = Exception.message(e)
        stacktrace = Exception.format_stacktrace(__STACKTRACE__)

        Ysc.Logging.error(
          "send_expense_report_emails_impl: Failed to schedule expense report confirmation email - #{exception_type}: #{exception_message}\n\nStacktrace:\n#{stacktrace}",
          expense_report_id: expense_report.id,
          exception_type: inspect(exception_type),
          exception_message: exception_message,
          exception: inspect(e, limit: :infinity),
          stacktrace: stacktrace,
          user_email:
            if(expense_report.user, do: expense_report.user.email, else: nil),
          user_id:
            if(expense_report.user, do: expense_report.user.id, else: nil)
        )
    end

    # Send notification email to Treasurer
    try do
      Ysc.Logging.info(
        "send_expense_report_emails_impl: Querying for treasurer",
        expense_report_id: expense_report.id
      )

      treasurer =
        from(u in User,
          where: u.board_position == "treasurer" and u.state == :active,
          limit: 1
        )
        |> Repo.one()

      Ysc.Logging.info(
        "send_expense_report_emails_impl: Treasurer query result",
        expense_report_id: expense_report.id,
        treasurer_found: !is_nil(treasurer),
        treasurer_email: if(treasurer, do: treasurer.email, else: nil),
        treasurer_id: if(treasurer, do: treasurer.id, else: nil)
      )

      if treasurer do
        Ysc.Logging.info(
          "send_expense_report_emails_impl: Preparing treasurer notification email data",
          expense_report_id: expense_report.id,
          treasurer_email: treasurer.email
        )

        email_data =
          ExpenseReportTreasurerNotification.prepare_email_data(expense_report)

        Ysc.Logging.info(
          "send_expense_report_emails_impl: Treasurer email data prepared",
          expense_report_id: expense_report.id,
          email_data_keys: Map.keys(email_data),
          email_data_expense_report_keys: Map.keys(email_data.expense_report),
          email_data_user_keys: Map.keys(email_data.user)
        )

        subject = ExpenseReportTreasurerNotification.get_subject()

        idempotency_key =
          "expense_report_treasurer_notification_#{expense_report.id}"

        template_name = ExpenseReportTreasurerNotification.get_template_name()

        Ysc.Logging.info(
          "send_expense_report_emails_impl: Calling Notifier.schedule_email for treasurer",
          expense_report_id: expense_report.id,
          recipient: treasurer.email,
          subject: subject,
          idempotency_key: idempotency_key,
          template_name: template_name,
          template_module: inspect(ExpenseReportTreasurerNotification),
          user_id: nil,
          email_data_type: inspect(email_data, limit: 200),
          email_data_keys: Map.keys(email_data)
        )

        result =
          Notifier.schedule_email(
            treasurer.email,
            idempotency_key,
            subject,
            template_name,
            email_data,
            "",
            nil
          )

        case result do
          {:error, _reason} ->
            Ysc.Logging.warning(
              "Failed to schedule expense report treasurer notification email",
              expense_report_id: expense_report.id,
              recipient: treasurer.email,
              result: inspect(result, limit: 100)
            )

          _ ->
            Ysc.Logging.debug(
              "Scheduled expense report treasurer notification email",
              expense_report_id: expense_report.id,
              recipient: treasurer.email
            )
        end
      else
        Ysc.Logging.warning(
          "No active treasurer found, skipping treasurer notification email",
          expense_report_id: expense_report.id
        )
      end
    rescue
      e ->
        exception_type = e.__struct__
        exception_message = Exception.message(e)
        stacktrace = Exception.format_stacktrace(__STACKTRACE__)

        Ysc.Logging.error(
          "send_expense_report_emails_impl: Failed to schedule expense report treasurer notification email - #{exception_type}: #{exception_message}\n\nStacktrace:\n#{stacktrace}",
          expense_report_id: expense_report.id,
          exception_type: inspect(exception_type),
          exception_message: exception_message,
          exception: inspect(e, limit: :infinity),
          stacktrace: stacktrace
        )
    end
  end

  def delete_expense_report(%ExpenseReport{} = expense_report) do
    Repo.delete(expense_report)
  end

  # Bank Accounts

  @doc """
  Lists bank accounts for a user. Returns structs with encrypted fields.

  **IMPORTANT**: The encrypted fields (account_number, routing_number) are stored encrypted
  and will only be decrypted if you access them directly. This function returns structs
  that have NOT been decrypted. Only access `.account_number_last_4` from these structs.

  Use `get_decrypted_bank_account/2` if you need the actual decrypted account/routing numbers.
  """
  def list_bank_accounts(%User{} = user) do
    Repo.all(
      from ba in BankAccount,
        where: ba.user_id == ^user.id,
        order_by: [desc: :inserted_at]
    )
  end

  @doc """
  Gets a bank account by ID. Returns struct with encrypted fields.
  The encrypted fields are NOT automatically decrypted.
  Use `get_decrypted_bank_account/2` if you need the decrypted values.
  """
  def get_bank_account!(id, %User{} = user) do
    Repo.one!(
      from ba in BankAccount,
        where: ba.id == ^id and ba.user_id == ^user.id
    )
  end

  @doc """
  Gets a bank account by ID. Returns struct with encrypted fields.
  The encrypted fields are NOT automatically decrypted.
  Use `get_decrypted_bank_account/2` if you need the decrypted values.
  """
  def get_bank_account(id, %User{} = user) do
    Repo.one(
      from ba in BankAccount,
        where: ba.id == ^id and ba.user_id == ^user.id
    )
  end

  @doc """
  Gets a bank account with decrypted account and routing numbers.
  Use this ONLY when you need the actual decrypted values (e.g., for processing payments).
  """
  def get_decrypted_bank_account(id, %User{} = user) do
    case get_bank_account(id, user) do
      nil -> nil
      bank_account -> BankAccount.get_decrypted_details(bank_account)
    end
  end

  @doc """
  Gets a bank account with decrypted account and routing numbers (raises if not found).
  Use this ONLY when you need the actual decrypted values (e.g., for processing payments).
  """
  def get_decrypted_bank_account!(id, %User{} = user) do
    bank_account = get_bank_account!(id, user)
    BankAccount.get_decrypted_details(bank_account)
  end

  def create_bank_account(attrs, %User{} = user) do
    %BankAccount{}
    |> BankAccount.changeset(Map.put(attrs, "user_id", user.id))
    |> Repo.insert()
  end

  def update_bank_account(%BankAccount{} = bank_account, attrs) do
    bank_account
    |> BankAccount.changeset(attrs)
    |> Repo.update()
  end

  def delete_bank_account(%BankAccount{} = bank_account) do
    Repo.delete(bank_account)
  end

  # Calculations

  def calculate_totals(%ExpenseReport{} = expense_report) do
    if preloaded_items?(expense_report) do
      calculate_totals_from_preloaded(expense_report)
    else
      calculate_totals_from_db(expense_report)
    end
  end

  defp preloaded_items?(%ExpenseReport{
         expense_items: expense_items,
         income_items: income_items
       }) do
    Ecto.assoc_loaded?(expense_items) and Ecto.assoc_loaded?(income_items)
  end

  defp calculate_totals_from_preloaded(%ExpenseReport{} = expense_report) do
    expense_total = sum_item_amounts(expense_report.expense_items)
    income_total = sum_item_amounts(expense_report.income_items)
    net_total = money_sub_or_zero(expense_total, income_total)

    %{
      expense_total: expense_total,
      income_total: income_total,
      net_total: net_total
    }
  end

  defp calculate_totals_from_db(%ExpenseReport{id: expense_report_id}) do
    expense_total =
      case Repo.one(
             from ei in ExpenseReportItem,
               where: ei.expense_report_id == ^expense_report_id,
               select: sum(fragment("(?.amount).amount", ei))
           ) do
        nil -> Money.new(0, :USD)
        amount -> Money.new(amount, :USD)
      end

    income_total =
      case Repo.one(
             from ii in ExpenseReportIncomeItem,
               where: ii.expense_report_id == ^expense_report_id,
               select: sum(fragment("(?.amount).amount", ii))
           ) do
        nil -> Money.new(0, :USD)
        amount -> Money.new(amount, :USD)
      end

    net_total = money_sub_or_zero(expense_total, income_total)

    %{
      expense_total: expense_total,
      income_total: income_total,
      net_total: net_total
    }
  end

  defp sum_item_amounts(items) do
    Enum.reduce(items, Money.new(0, :USD), fn item, acc ->
      case Money.add(acc, item.amount) do
        {:ok, result} -> result
        _ -> acc
      end
    end)
  end

  defp money_sub_or_zero(expense_total, income_total) do
    case Money.sub(expense_total, income_total) do
      {:ok, result} -> result
      _ -> Money.new(0, :USD)
    end
  end

  # S3 Upload for Expense Reports
  #
  # IMPORTANT: The expense-reports bucket is BACKEND-ONLY.
  # - Files are uploaded to the LiveView server first (via allow_upload)
  # - The backend then uploads to S3 using ExAws with backend credentials
  # - The bucket has NO CORS configuration, preventing direct frontend access
  # - All access uses AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY from environment

  @doc """
  Uploads a file directly to S3 in the expense reports bucket.
  This function is called by the backend after receiving the file from the LiveView upload.
  Returns the S3 path (key) for the uploaded file.

  Uses backend credentials configured via ExAws (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY).

  ## Parameters
  - `path` - The temporary file path from the upload
  - `opts` - Required:
    - `:user_id` - Owner of the upload (prevents IDOR on unsaved-file preview; must match session user)
  - Optional:
    - `:original_filename` - The original filename from the client (preserves file extension)
    - `:kind` - `:receipt` (default) or `:proof` — controls `receipts/` vs `proofs/` prefix
  """
  def upload_receipt_to_s3(path, opts \\ []) do
    require Ysc.Logging
    user_id = Keyword.fetch!(opts, :user_id)
    kind = Keyword.get(opts, :kind, :receipt)
    original_filename = Keyword.get(opts, :original_filename)
    prefix = upload_s3_key_prefix_for_kind(kind)

    # Use original filename if provided to preserve extension, otherwise use basename of temp file
    file_name =
      if original_filename do
        # Sanitize the filename but preserve the extension
        sanitized =
          original_filename
          |> String.replace(~r/[^a-zA-Z0-9._-]/, "_")
          |> String.replace(~r/_+/, "_")

        sanitized
      else
        Path.basename(path)
      end

    # Generate a unique key with timestamp; user_id prefix prevents other users' preview URLs (IDOR)
    timestamp = System.system_time(:second)
    unique_key = "#{prefix}/#{user_id}/#{timestamp}_#{file_name}"
    bucket_name = S3Config.expense_reports_bucket_name()

    Ysc.Logging.debug("Uploading receipt to S3",
      path: path,
      bucket: bucket_name,
      key: unique_key,
      original_filename: original_filename
    )

    result =
      case Application.get_env(:ysc, :expense_reports_s3_upload) do
        nil ->
          upload_op =
            path
            |> ExAws.S3.Upload.stream_file()
            |> ExAws.S3.upload(bucket_name, unique_key,
              cache_control: "public, max-age=86400"
            )

          expense_report_s3_upload_request!(upload_op)

        upload_module when is_atom(upload_module) ->
          upload_module.upload(path, bucket_name, unique_key)
      end

    Ysc.Logging.debug("S3 upload result", result: inspect(result, limit: 10))

    # Return the S3 path (key) - the full URL can be constructed using S3Config.object_url/2
    key = result[:body][:key] || unique_key
    Ysc.Logging.debug("Returning S3 key", key: key)
    key
  end

  @doc """
  Constructs the full URL for an expense report receipt/proof stored in S3.
  Returns a controller route that generates presigned URLs for secure access.
  """
  def receipt_url(s3_path) when is_binary(s3_path) do
    # Base64 encode the S3 path to safely handle special characters in the URL
    encoded_path = Base.url_encode64(s3_path, padding: false)
    "/expensereport/files/#{encoded_path}"
  end

  def receipt_url(_), do: nil

  @doc """
  Checks if a user can access a file by verifying they own the expense report
  that contains the file, or if they are an admin. Also allows access to recently
  uploaded files (within 24 hours) that haven't been submitted yet, so users can
  preview their uploads during form editing.

  Returns:
  - `{:ok, expense_report}` if the user has access (expense_report may be nil for unsaved reports)
  - `{:error, :not_found}` if the file is not found in any expense report and not recently uploaded
  - `{:error, :unauthorized}` if the user does not own the expense report and is not an admin
  """
  def can_access_file?(%User{} = user, s3_path) when is_binary(s3_path) do
    # Check if user is admin - admins can access any file
    is_admin = user.role == :admin

    # Normalize the S3 path - remove bucket name prefix if present
    # The database stores just the key (e.g., "receipts/..."), not "bucket-name/receipts/..."
    normalized_path = normalize_s3_path(s3_path)

    # First, try to find the file in expense_report_items (for submitted reports)
    expense_item_query =
      from eri in ExpenseReportItem,
        join: er in ExpenseReport,
        on: eri.expense_report_id == er.id,
        where: eri.receipt_s3_path == ^normalized_path,
        select: er

    expense_report = Repo.one(expense_item_query)

    if expense_report do
      # Check if user owns the report or is admin
      if expense_report.user_id == user.id || is_admin do
        {:ok, expense_report}
      else
        {:error, :unauthorized}
      end
    else
      # If not found in expense items, check income items (for submitted reports)
      income_item_query =
        from erii in ExpenseReportIncomeItem,
          join: er in ExpenseReport,
          on: erii.expense_report_id == er.id,
          where: erii.proof_s3_path == ^normalized_path,
          select: er

      expense_report = Repo.one(income_item_query)

      if expense_report do
        # Check if user owns the report or is admin
        if expense_report.user_id == user.id || is_admin do
          {:ok, expense_report}
        else
          {:error, :unauthorized}
        end
      else
        # File not found in any submitted expense report
        # Check if it's a recently uploaded file (for preview during form editing)
        # Files uploaded via LiveView have timestamps in their names like: receipts/1767121378_filename
        if recently_uploaded_unsaved_accessible?(
             user,
             normalized_path,
             is_admin
           ) do
          # Unsaved in-DB: user-scoped key receipts|proofs/USER_ID/TIMESTAMP_name (24h)
          {:ok, nil}
        else
          {:error, :not_found}
        end
      end
    end
  end

  def can_access_file?(_, _), do: {:error, :not_found}

  defp upload_s3_key_prefix_for_kind(:receipt), do: "receipts"
  defp upload_s3_key_prefix_for_kind(:proof), do: "proofs"
  defp upload_s3_key_prefix_for_kind(_), do: "receipts"

  # Normalizes S3 path by removing bucket name prefix if present
  # The database stores just the key (e.g., "receipts/..."), not "bucket-name/receipts/..."
  defp normalize_s3_path(s3_path) do
    bucket_name = S3Config.expense_reports_bucket_name()
    prefix = "#{bucket_name}/"

    if String.starts_with?(s3_path, prefix) do
      String.replace_prefix(s3_path, prefix, "")
    else
      s3_path
    end
  end

  # Unsaved upload preview: keys must be receipts|proofs/<user_id>/<unix_ts>_<name> and within 24h.
  # Legacy keys without /<user_id>/ are not granted unsaved access (fixes cross-user IDOR).
  defp recently_uploaded_unsaved_accessible?(%User{} = user, s3_path, is_admin) do
    with {:ok, path_user_id, timestamp} <-
           parse_user_scoped_upload_path(s3_path),
         true <- within_last_24h_unix?(timestamp) do
      is_admin or path_user_id == user.id
    else
      _ -> false
    end
  end

  defp parse_user_scoped_upload_path(s3_path) do
    case Regex.run(~r{\A(receipts|proofs)/([^/]+)/(\d+)_}, s3_path) do
      [_, _kind, user_id, ts] ->
        case Integer.parse(ts) do
          {unix, _} -> {:ok, user_id, unix}
          :error -> :error
        end

      _ ->
        :error
    end
  end

  defp within_last_24h_unix?(timestamp) do
    file_time = DateTime.from_unix!(timestamp, :second)
    now = DateTime.utc_now()
    DateTime.diff(now, file_time, :hour) <= 24
  end

  defp expense_report_s3_upload_request!(op) do
    request_fn =
      Application.get_env(:ysc, :expense_reports_s3_request, &ExAws.request!/1)

    request_fn.(op)
  end

  defp validate_check_reimbursement_method(changeset, user) do
    address_id = Ecto.Changeset.get_field(changeset, :address_id)
    billing_address = Ysc.Accounts.get_billing_address(user)

    if is_nil(address_id) do
      handle_missing_address_id(changeset, billing_address)
    else
      changeset
    end
  end

  defp handle_missing_address_id(changeset, billing_address) do
    if is_nil(billing_address) do
      Ecto.Changeset.add_error(
        changeset,
        :reimbursement_method,
        "requires a billing address. Please add an address in your user settings before submitting."
      )
    else
      # Auto-set the billing address if available
      Ecto.Changeset.put_change(changeset, :address_id, billing_address.id)
    end
  end

  @doc false
  def ci_query_explain_query do
    alias Ysc.Ci.QueryExplain.Fixtures

    user_id = Fixtures.ulid()

    from(er in ExpenseReport,
      where: er.user_id == ^user_id,
      order_by: [desc: er.inserted_at],
      preload: [:expense_items, :income_items, :address, :event]
    )
  end

  defp validate_and_send_expense_report_emails(loaded_report) do
    # Validate that we have required associations
    if is_nil(loaded_report.user) do
      Ysc.Logging.error(
        "Cannot send emails: expense report missing user association",
        expense_report_id: loaded_report.id
      )

      :ok
    else
      send_expense_report_emails_impl(loaded_report)
    end
  end
end
