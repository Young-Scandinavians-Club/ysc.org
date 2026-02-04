defmodule Ysc.ExpenseReports do
  @moduledoc """
  Context module for managing expense reports.
  """
  require Logger
  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.Accounts.User

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
    Repo.all(
      from er in ExpenseReport,
        where: er.user_id == ^user.id,
        order_by: [desc: :inserted_at],
        preload: [:expense_items, :income_items, :address, :event]
    )
    |> Enum.map(fn report ->
      # Load bank_account separately without accessing encrypted fields
      bank_account =
        if report.bank_account_id do
          Repo.get(BankAccount, report.bank_account_id)
        else
          nil
        end

      %{report | bank_account: bank_account}
    end)
  end

  def get_expense_report!(id, %User{} = user) do
    report =
      Repo.one!(
        from er in ExpenseReport,
          where: er.id == ^id and er.user_id == ^user.id,
          preload: [:expense_items, :income_items, :address, :event]
      )

    # Load bank_account separately without accessing encrypted fields
    bank_account =
      if report.bank_account_id do
        Repo.get(BankAccount, report.bank_account_id)
      else
        nil
      end

    %{report | bank_account: bank_account}
  end

  def create_expense_report(attrs, %User{} = user) do
    require Logger

    # Set status to "submitted" if not already set (for submissions)
    attrs = Map.put_new(attrs, "status", "submitted")

    changeset =
      %ExpenseReport{}
      |> ExpenseReport.changeset(
        Map.put(attrs, "user_id", user.id),
        validate_address_ownership: true,
        validate_bank_account_ownership: true
      )
      |> validate_reimbursement_setup(user)
      |> validate_all_expense_items_have_receipts_for_submission()

    Logger.debug(
      "Expense report changeset - valid?: #{changeset.valid?}, errors: #{inspect(changeset.errors, limit: 20)}"
    )

    # Check for nested association errors
    expense_items = Ecto.Changeset.get_field(changeset, :expense_items, [])
    Logger.debug("Expense items count: #{length(expense_items)}")

    Enum.with_index(expense_items)
    |> Enum.each(fn {item, idx} ->
      case item do
        %Ecto.Changeset{} = cs ->
          receipt_path = Ecto.Changeset.get_field(cs, :receipt_s3_path)

          Logger.debug(
            "Expense item #{idx} - valid?: #{cs.valid?}, errors: #{inspect(cs.errors, limit: 10)}, receipt: #{inspect(receipt_path)}"
          )

        struct ->
          receipt_path = Map.get(struct, :receipt_s3_path)

          Logger.debug(
            "Expense item #{idx} - struct, receipt: #{inspect(receipt_path)}"
          )
      end
    end)

    # Also check if there are changeset errors in the associations
    if Map.has_key?(changeset.changes, :expense_items) do
      Logger.debug("expense_items in changes - checking for errors")

      case changeset.changes[:expense_items] do
        list when is_list(list) ->
          Enum.with_index(list)
          |> Enum.each(fn {item, idx} ->
            case item do
              %Ecto.Changeset{} = cs ->
                Logger.debug(
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
          Logger.debug(
            "Expense report created with submitted status, enqueueing QuickBooks sync",
            expense_report_id: expense_report.id
          )

          enqueue_quickbooks_sync(expense_report)
          send_expense_report_emails(expense_report)
        else
          Logger.debug(
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

  def update_expense_report(%ExpenseReport{} = expense_report, attrs) do
    expense_report
    |> ExpenseReport.changeset(attrs)
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
    Logger.debug("Starting enqueue_quickbooks_sync",
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
        Logger.debug("Marked expense report as pending sync",
          expense_report_id: updated_report.id
        )

        # Enqueue Oban job
        job_result =
          %{"expense_report_id" => expense_report.id}
          |> YscWeb.Workers.QuickbooksSyncExpenseReportWorker.new()
          |> Oban.insert()

        case job_result do
          {:ok, job} ->
            Logger.info("Enqueued QuickBooks sync for expense report",
              expense_report_id: expense_report.id,
              job_id: job.id,
              queue: job.queue,
              scheduled_at: job.scheduled_at
            )

          {:error, reason} ->
            Logger.error("Failed to enqueue QuickBooks sync for expense report",
              expense_report_id: expense_report.id,
              error: inspect(reason)
            )

            Sentry.capture_message(
              "Failed to enqueue QuickBooks sync for expense report",
              level: :error,
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
        Logger.error("Failed to mark expense report as pending sync",
          expense_report_id: expense_report.id,
          errors: inspect(changeset.errors)
        )
    end
  end

  defp send_expense_report_emails(%ExpenseReport{} = expense_report) do
    require Logger

    # Ensure expense report has an ID (must be saved to database)
    if is_nil(expense_report.id) do
      Logger.warning("Cannot send emails for expense report without ID",
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
          Logger.error(
            "Expense report not found in database when sending emails",
            expense_report_id: expense_report.id
          )

          :ok

        loaded_report ->
          validate_and_send_expense_report_emails(loaded_report)
      end
    end
  end

  defp send_expense_report_emails_impl(%ExpenseReport{} = expense_report) do
    require Logger

    Logger.info("send_expense_report_emails_impl: Starting email sending",
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
      Logger.info(
        "send_expense_report_emails_impl: Preparing confirmation email data",
        expense_report_id: expense_report.id,
        user_email:
          if(expense_report.user, do: expense_report.user.email, else: nil)
      )

      email_data = ExpenseReportConfirmation.prepare_email_data(expense_report)

      Logger.info("send_expense_report_emails_impl: Email data prepared",
        expense_report_id: expense_report.id,
        email_data_keys: Map.keys(email_data),
        email_data_expense_report_keys:
          if(Map.has_key?(email_data, :expense_report),
            do: Map.keys(email_data.expense_report),
            else: :not_present
          ),
        email_data_first_name: Map.get(email_data, :first_name),
        expense_items_count:
          if(
            Map.has_key?(email_data, :expense_report) &&
              Map.has_key?(email_data.expense_report, :expense_items),
            do: length(email_data.expense_report.expense_items),
            else: :not_present
          )
      )

      subject = ExpenseReportConfirmation.get_subject()
      idempotency_key = "expense_report_confirmation_#{expense_report.id}"

      template_name = ExpenseReportConfirmation.get_template_name()

      Logger.info(
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
          Logger.warning("Failed to schedule expense report confirmation email",
            expense_report_id: expense_report.id,
            recipient: expense_report.user.email,
            result: inspect(result, limit: 100)
          )

        _ ->
          Logger.debug("Scheduled expense report confirmation email",
            expense_report_id: expense_report.id,
            recipient: expense_report.user.email
          )
      end
    rescue
      e ->
        exception_type = e.__struct__
        exception_message = Exception.message(e)
        stacktrace = Exception.format_stacktrace(__STACKTRACE__)

        Logger.error(
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
      Logger.info("send_expense_report_emails_impl: Querying for treasurer",
        expense_report_id: expense_report.id
      )

      treasurer =
        from(u in User,
          where: u.board_position == "treasurer" and u.state == :active
        )
        |> Repo.one()

      Logger.info("send_expense_report_emails_impl: Treasurer query result",
        expense_report_id: expense_report.id,
        treasurer_found: !is_nil(treasurer),
        treasurer_email: if(treasurer, do: treasurer.email, else: nil),
        treasurer_id: if(treasurer, do: treasurer.id, else: nil)
      )

      if treasurer do
        Logger.info(
          "send_expense_report_emails_impl: Preparing treasurer notification email data",
          expense_report_id: expense_report.id,
          treasurer_email: treasurer.email
        )

        email_data =
          ExpenseReportTreasurerNotification.prepare_email_data(expense_report)

        Logger.info(
          "send_expense_report_emails_impl: Treasurer email data prepared",
          expense_report_id: expense_report.id,
          email_data_keys: Map.keys(email_data),
          email_data_expense_report_keys:
            if(Map.has_key?(email_data, :expense_report),
              do: Map.keys(email_data.expense_report),
              else: :not_present
            ),
          email_data_user_keys:
            if(Map.has_key?(email_data, :user),
              do: Map.keys(email_data.user),
              else: :not_present
            )
        )

        subject = ExpenseReportTreasurerNotification.get_subject()

        idempotency_key =
          "expense_report_treasurer_notification_#{expense_report.id}"

        template_name = ExpenseReportTreasurerNotification.get_template_name()

        Logger.info(
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
            Logger.warning(
              "Failed to schedule expense report treasurer notification email",
              expense_report_id: expense_report.id,
              recipient: treasurer.email,
              result: inspect(result, limit: 100)
            )

          _ ->
            Logger.debug(
              "Scheduled expense report treasurer notification email",
              expense_report_id: expense_report.id,
              recipient: treasurer.email
            )
        end
      else
        Logger.warning(
          "No active treasurer found, skipping treasurer notification email",
          expense_report_id: expense_report.id
        )
      end
    rescue
      e ->
        exception_type = e.__struct__
        exception_message = Exception.message(e)
        stacktrace = Exception.format_stacktrace(__STACKTRACE__)

        Logger.error(
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
    expense_total =
      case Repo.one(
             from ei in ExpenseReportItem,
               where: ei.expense_report_id == ^expense_report.id,
               select: sum(fragment("(?.amount).amount", ei))
           ) do
        nil -> Money.new(0, :USD)
        amount -> Money.new(amount, :USD)
      end

    income_total =
      case Repo.one(
             from ii in ExpenseReportIncomeItem,
               where: ii.expense_report_id == ^expense_report.id,
               select: sum(fragment("(?.amount).amount", ii))
           ) do
        nil -> Money.new(0, :USD)
        amount -> Money.new(amount, :USD)
      end

    net_total =
      case Money.sub(expense_total, income_total) do
        {:ok, result} -> result
        _ -> Money.new(0, :USD)
      end

    %{
      expense_total: expense_total,
      income_total: income_total,
      net_total: net_total
    }
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
  - `opts` - Optional keyword list with:
    - `:original_filename` - The original filename from the client (preserves file extension)
  """
  def upload_receipt_to_s3(path, opts \\ []) do
    require Logger
    original_filename = Keyword.get(opts, :original_filename)

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

    # Generate a unique key with timestamp to avoid collisions
    timestamp = System.system_time(:second)
    unique_key = "receipts/#{timestamp}_#{file_name}"
    bucket_name = S3Config.expense_reports_bucket_name()

    Logger.debug("Uploading receipt to S3",
      path: path,
      bucket: bucket_name,
      key: unique_key,
      original_filename: original_filename
    )

    result =
      path
      |> ExAws.S3.Upload.stream_file()
      |> ExAws.S3.upload(bucket_name, unique_key)
      |> ExAws.request!()

    Logger.debug("S3 upload result", result: inspect(result, limit: 10))

    # Return the S3 path (key) - the full URL can be constructed using S3Config.object_url/2
    key = result[:body][:key] || unique_key
    Logger.debug("Returning S3 key", key: key)
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
        if recently_uploaded_file?(normalized_path) do
          # Allow access to recently uploaded files (within 24 hours)
          # This allows users to preview their uploads before submitting the form
          {:ok, nil}
        else
          {:error, :not_found}
        end
      end
    end
  end

  def can_access_file?(_, _), do: {:error, :not_found}

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

  # Checks if a file was recently uploaded (within 24 hours) based on timestamp in filename
  # LiveView uploads have format: receipts/TIMESTAMP_filename
  defp recently_uploaded_file?(s3_path) do
    # Extract timestamp from path like "receipts/1767121378_filename" or "receipts/1767121378_live_view_upload-..."
    case Regex.run(~r/receipts\/(\d+)_/, s3_path) ||
           Regex.run(~r/proofs\/(\d+)_/, s3_path) do
      [_full_match, timestamp_str] ->
        case Integer.parse(timestamp_str) do
          {timestamp, _} ->
            # Check if timestamp is within last 24 hours
            file_time = DateTime.from_unix!(timestamp, :second)
            now = DateTime.utc_now()
            hours_ago = DateTime.diff(now, file_time, :hour)
            hours_ago <= 24

          :error ->
            false
        end

      _ ->
        false
    end
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

  defp validate_and_send_expense_report_emails(loaded_report) do
    # Validate that we have required associations
    if is_nil(loaded_report.user) do
      Logger.error(
        "Cannot send emails: expense report missing user association",
        expense_report_id: loaded_report.id
      )

      :ok
    else
      send_expense_report_emails_impl(loaded_report)
    end
  end
end
