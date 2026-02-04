defmodule Ysc.ExpenseReports.QuickbooksSync do
  @moduledoc """
  Handles syncing ExpenseReport records to QuickBooks as Bills.

  This module provides functions to sync expense reports to QuickBooks Online,
  creating vendors, bills, and uploading receipts.
  """

  require Logger
  alias Ysc.Repo
  alias Ysc.ExpenseReports.ExpenseReport
  alias Ysc.Accounts.User
  alias Ysc.S3Config
  alias FileType

  # Helper to get the configured QuickBooks client module (for testing with mocks)
  defp client_module do
    Application.get_env(:ysc, :quickbooks_client, Ysc.Quickbooks.Client)
  end

  @doc """
  Syncs an expense report to QuickBooks as a Bill.

  Returns {:ok, bill} on success, {:error, reason} on failure.
  """
  @spec sync_expense_report(ExpenseReport.t()) ::
          {:ok, map()} | {:error, atom() | String.t()}
  def sync_expense_report(%ExpenseReport{} = expense_report) do
    Logger.info("[QB Expense Sync] Starting sync for expense report",
      expense_report_id: expense_report.id,
      sync_status: expense_report.quickbooks_sync_status,
      bill_id: expense_report.quickbooks_bill_id
    )

    # Idempotency check: If we already have a bill_id, don't create a new one
    # This prevents duplicate bills even if status isn't "synced" yet (e.g., if sync was interrupted)
    if expense_report.quickbooks_bill_id do
      Logger.info(
        "[QB Expense Sync] Expense report already has a QuickBooks bill ID, skipping creation",
        expense_report_id: expense_report.id,
        bill_id: expense_report.quickbooks_bill_id,
        sync_status: expense_report.quickbooks_sync_status
      )

      # If status is not "synced", update it to "synced" to mark as complete
      if expense_report.quickbooks_sync_status != "synced" do
        Logger.info(
          "[QB Expense Sync] Updating sync status to 'synced' for existing bill",
          expense_report_id: expense_report.id,
          bill_id: expense_report.quickbooks_bill_id
        )

        update_expense_report_success(
          expense_report,
          expense_report.quickbooks_vendor_id,
          expense_report.quickbooks_bill_id
        )
      end

      {:ok, %{"Id" => expense_report.quickbooks_bill_id}}
    else
      # Update last sync attempt timestamp
      update_sync_attempt_timestamp(expense_report)

      # Ensure associations are loaded (they should already be preloaded by the worker)
      expense_report =
        if Ecto.assoc_loaded?(expense_report.user) &&
             Ecto.assoc_loaded?(expense_report.expense_items) do
          Logger.debug("[QB Expense Sync] Associations already loaded",
            expense_report_id: expense_report.id
          )

          expense_report
        else
          Logger.debug(
            "[QB Expense Sync] Associations not loaded, preloading now",
            expense_report_id: expense_report.id,
            user_loaded: Ecto.assoc_loaded?(expense_report.user),
            expense_items_loaded:
              Ecto.assoc_loaded?(expense_report.expense_items)
          )

          expense_report
          |> Repo.preload([
            :expense_items,
            :income_items,
            :address,
            :bank_account,
            :event
          ])
          |> Repo.preload(user: :billing_address)
        end

      with {:ok, vendor_id} <- get_or_create_vendor(expense_report.user),
           {:ok, bill} <- create_bill(expense_report, vendor_id) do
        # Store bill_id immediately after creation for idempotency
        # This prevents duplicate bills if receipt upload fails or is retried
        bill_id = bill["Id"]

        Logger.info(
          "[QB Expense Sync] Bill created, storing bill_id for idempotency",
          expense_report_id: expense_report.id,
          bill_id: bill_id
        )

        # Store bill_id and vendor_id immediately (even if receipt upload fails later)
        # This ensures idempotency - if we retry, we won't create a duplicate bill
        case update_expense_report_with_bill_id(
               expense_report,
               vendor_id,
               bill_id
             ) do
          {:ok, _} ->
            # Now try to upload receipts (non-blocking - bill is already created)
            # upload_and_link_receipts always returns {:ok, status} where status is
            # :no_files, :partial_success, or :success
            {:ok, receipt_status} =
              upload_and_link_receipts(expense_report, bill_id)

            # Log receipt upload status
            case receipt_status do
              :no_files ->
                Logger.info("[QB Expense Sync] No receipts to upload",
                  expense_report_id: expense_report.id,
                  bill_id: bill_id
                )

              :partial_success ->
                Logger.warning(
                  "[QB Expense Sync] Bill created but some receipt uploads failed (non-critical)",
                  expense_report_id: expense_report.id,
                  bill_id: bill_id
                )

              :success ->
                Logger.info(
                  "[QB Expense Sync] All receipts uploaded successfully",
                  expense_report_id: expense_report.id,
                  bill_id: bill_id
                )
            end

            # Mark as fully synced (bill is created, which is the important part)
            update_expense_report_success(expense_report, vendor_id, bill_id)

            Logger.info(
              "[QB Expense Sync] Successfully synced expense report to QuickBooks",
              expense_report_id: expense_report.id,
              bill_id: bill_id,
              receipt_status: receipt_status
            )

            {:ok, bill}

          {:error, update_error} ->
            Logger.error(
              "[QB Expense Sync] Failed to store bill_id after creation",
              expense_report_id: expense_report.id,
              bill_id: bill_id,
              error: inspect(update_error)
            )

            # This is a critical error - we created a bill but can't store the ID
            # This could lead to duplicate bills on retry
            {:error, :failed_to_store_bill_id}
        end
      else
        {:error, reason} = error ->
          update_expense_report_error(expense_report, reason)

          Logger.error(
            "[QB Expense Sync] Failed to sync expense report to QuickBooks",
            expense_report_id: expense_report.id,
            error: inspect(reason)
          )

          # Report to Sentry
          Sentry.capture_message("QuickBooks expense report sync failed",
            level: :error,
            extra: %{
              expense_report_id: expense_report.id,
              error: inspect(reason)
            },
            tags: %{
              quickbooks_operation: "sync_expense_report",
              expense_report_id: expense_report.id
            }
          )

          error
      end
    end
  end

  defp get_or_create_vendor(%User{} = user) do
    # Handle nil first_name or last_name
    first_name = user.first_name || ""
    last_name = user.last_name || ""
    display_name = String.trim("#{first_name} #{last_name}")

    # Fallback to email if name is empty
    display_name =
      if display_name == "" do
        user.email || "User #{user.id}"
      else
        display_name
      end

    Logger.debug(
      "[QB Expense Sync] get_or_create_vendor: Getting or creating vendor",
      display_name: display_name,
      user_id: user.id,
      first_name: first_name,
      last_name: last_name,
      email: user.email
    )

    vendor_params = %{
      given_name: first_name,
      family_name: last_name,
      email: user.email
    }

    # Add billing address if available and loaded
    vendor_params =
      if Ecto.assoc_loaded?(user.billing_address) do
        case user.billing_address do
          nil ->
            Logger.debug(
              "[QB Expense Sync] get_or_create_vendor: Billing address is nil"
            )

            vendor_params

          billing_address ->
            Map.put(vendor_params, :bill_address, %{
              line1: billing_address.address,
              city: billing_address.city,
              country_sub_division_code: billing_address.region,
              postal_code: billing_address.postal_code,
              country: billing_address.country || "USA"
            })
        end
      else
        Logger.debug(
          "[QB Expense Sync] get_or_create_vendor: Billing address not loaded"
        )

        vendor_params
      end

    Logger.debug(
      "[QB Expense Sync] get_or_create_vendor: Calling QuickBooks client",
      display_name: display_name,
      vendor_params: Map.keys(vendor_params)
    )

    result = client_module().get_or_create_vendor(display_name, vendor_params)

    case result do
      {:ok, vendor_id} ->
        Logger.info("[QB Expense Sync] get_or_create_vendor: Vendor obtained",
          vendor_id: vendor_id,
          display_name: display_name
        )

        {:ok, vendor_id}

      {:error, reason} ->
        Logger.error(
          "[QB Expense Sync] get_or_create_vendor: Failed to get or create vendor",
          display_name: display_name,
          error: inspect(reason),
          error_type: if(is_atom(reason), do: reason, else: :unknown)
        )

        {:error, reason}

      other ->
        Logger.error(
          "[QB Expense Sync] get_or_create_vendor: Unexpected result",
          display_name: display_name,
          result: inspect(other)
        )

        {:error, :unexpected_result}
    end
  end

  defp create_bill(%ExpenseReport{} = expense_report, vendor_id) do
    Logger.debug("[QB Expense Sync] create_bill: Creating bill",
      expense_report_id: expense_report.id,
      vendor_id: vendor_id
    )

    # Get default expense account (uncategorized expense) for line items
    # The treasurer will update this with proper accounts/classes later
    default_expense_account_id =
      case Application.get_env(:ysc, :quickbooks, [])[
             :default_expense_account_id
           ] do
        nil ->
          # Try to query for "Uncategorized Expense" account
          case client_module().query_account_by_name("Uncategorized Expense") do
            {:ok, account_id} -> account_id
            _ -> nil
          end

        account_id ->
          account_id
      end

    if is_nil(default_expense_account_id) do
      Logger.warning(
        "[QB Expense Sync] create_bill: No default expense account configured"
      )
    end

    # Get Accounts Payable account (separate from expense account)
    ap_account_id =
      case Application.get_env(:ysc, :quickbooks, [])[:ap_account_id] do
        nil ->
          # Try to query for "Accounts Payable" account
          case client_module().query_account_by_name("Accounts Payable") do
            {:ok, account_id} ->
              account_id

            _ ->
              case client_module().query_account_by_name(
                     "Accounts Payable (A/P)"
                   ) do
                {:ok, account_id} -> account_id
                _ -> nil
              end
          end

        account_id ->
          account_id
      end

    if is_nil(ap_account_id) do
      Logger.warning(
        "[QB Expense Sync] create_bill: No Accounts Payable account configured"
      )
    end

    # Get default income account for income items
    default_income_account_id =
      case Application.get_env(:ysc, :quickbooks, [])[
             :default_income_account_id
           ] do
        nil ->
          # Try to query for "General Revenue" account
          case client_module().query_account_by_name("General Revenue") do
            {:ok, account_id} ->
              account_id

            _ ->
              # Fallback to "Uncategorized Income" if General Revenue not found
              case client_module().query_account_by_name("Uncategorized Income") do
                {:ok, account_id} -> account_id
                _ -> nil
              end
          end

        account_id ->
          account_id
      end

    if is_nil(default_income_account_id) do
      Logger.warning(
        "[QB Expense Sync] create_bill: No default income account configured"
      )
    end

    # Build bill lines from expense items
    # Note: Currently using simple approach - default expense account for all items
    # The treasurer will update accounts/classes in QuickBooks after submission
    # When classification field is added to expense items, map it to Class ID using:
    #   client_module().query_class_by_name(classification_name)
    # or use query_all_classes() to get all classes and map user selection to ID
    expense_lines =
      expense_report.expense_items
      |> Enum.map(fn item ->
        amount = Money.to_decimal(item.amount) |> Decimal.to_float()

        # NOTE: When classification field is added to ExpenseReportItem schema,
        # query for Class ID and set class_ref here instead of nil
        # Example:
        #   class_ref = case item.classification do
        #     nil -> nil
        #     classification_name ->
        #       case client_module().query_class_by_name(classification_name) do
        #         {:ok, class_id} -> %{value: class_id}
        #         _ -> nil
        #       end
        #   end

        %{
          description: "#{item.vendor} - #{item.description}",
          amount: amount,
          account_ref: %{value: default_expense_account_id || ""},
          class_ref: nil
        }
      end)

    # Build bill lines from income items (as negative amounts to reduce the bill total)
    income_lines =
      expense_report.income_items
      |> Enum.map(fn item ->
        amount = Money.to_decimal(item.amount) |> Decimal.to_float()
        # Make amount negative to reduce the bill total
        negative_amount = -amount

        %{
          description: "Income: #{item.description}",
          amount: negative_amount,
          account_ref: %{value: default_income_account_id || ""},
          class_ref: nil
        }
      end)

    # Combine expense and income lines
    bill_lines = expense_lines ++ income_lines

    # Use the earliest date from both expense and income items as the transaction date
    all_dates =
      (expense_report.expense_items |> Enum.map(& &1.date)) ++
        (expense_report.income_items |> Enum.map(& &1.date))

    txn_date =
      if Enum.empty?(all_dates) do
        Date.utc_today() |> Date.to_iso8601()
      else
        all_dates |> Enum.min() |> Date.to_iso8601()
      end

    # Build private note with bank info if available
    private_note = build_private_note(expense_report)

    bill_params = %{
      vendor_ref: %{value: vendor_id},
      txn_date: txn_date,
      line: bill_lines,
      private_note: private_note
    }

    # Only set APAccountRef if we have an Accounts Payable account
    # QuickBooks will use a default if not specified, but it's better to be explicit
    bill_params =
      if ap_account_id do
        Map.put(bill_params, :ap_account_ref, %{value: ap_account_id})
      else
        bill_params
      end

    # Use expense report ID as idempotency key to prevent duplicate bills on retries
    idempotency_key = "expense_report_#{expense_report.id}"

    case client_module().create_bill(bill_params,
           idempotency_key: idempotency_key
         ) do
      {:ok, bill} ->
        Logger.info("[QB Expense Sync] create_bill: Successfully created bill",
          bill_id: Map.get(bill, "Id"),
          expense_report_id: expense_report.id,
          idempotency_key: idempotency_key
        )

        {:ok, bill}

      {:error, reason} ->
        Logger.error("[QB Expense Sync] create_bill: Failed to create bill",
          expense_report_id: expense_report.id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp build_private_note(%ExpenseReport{} = expense_report) do
    # Add expense report DB ID for reference
    report_id_note = "Expense Report ID: #{expense_report.id}"
    note_parts = [report_id_note, "Expense Report: #{expense_report.purpose}"]

    # Add event information if present
    note_parts =
      if expense_report.event_id && expense_report.event do
        event = expense_report.event
        event_info = "Related Event: #{event.title} (Event ID: #{event.id})"
        [event_info | note_parts]
      else
        note_parts
      end

    note_parts =
      case expense_report.reimbursement_method do
        "bank_transfer" ->
          if expense_report.bank_account do
            bank_account = expense_report.bank_account
            account_last_4 = bank_account.account_number_last_4 || "N/A"
            ["Bank Transfer - Account: ...#{account_last_4}" | note_parts]
          else
            ["Bank Transfer (account not specified)" | note_parts]
          end

        "check" ->
          check_note =
            "⚠️ CHECK REQUESTED - Please issue a physical check for this reimbursement"

          note_parts =
            if expense_report.address do
              addr = expense_report.address

              address_str =
                "#{addr.address}, #{addr.city}, #{addr.region} #{addr.postal_code}"

              ["Ship check to: #{address_str}" | note_parts]
            else
              [
                "⚠️ WARNING: Check requested but no shipping address on file"
                | note_parts
              ]
            end

          [check_note | note_parts]

        _ ->
          note_parts
      end

    Enum.join(note_parts, " | ")
  end

  defp upload_and_link_receipts(%ExpenseReport{} = expense_report, bill_id) do
    Logger.info(
      "[QB Expense Sync] upload_and_link_receipts: Starting receipt upload process",
      expense_report_id: expense_report.id,
      bill_id: bill_id,
      expense_items_loaded: Ecto.assoc_loaded?(expense_report.expense_items),
      total_expense_items:
        if(Ecto.assoc_loaded?(expense_report.expense_items),
          do: length(expense_report.expense_items),
          else: :not_loaded
        )
    )

    # Ensure expense_items are loaded
    # Load expense items if not already loaded
    expense_items =
      if Ecto.assoc_loaded?(expense_report.expense_items) do
        expense_report.expense_items
      else
        Logger.warning(
          "[QB Expense Sync] upload_and_link_receipts: Expense items not loaded, preloading now",
          expense_report_id: expense_report.id
        )

        expense_report
        |> Repo.preload(:expense_items)
        |> Map.get(:expense_items)
      end

    # Load income items if not already loaded
    income_items =
      if Ecto.assoc_loaded?(expense_report.income_items) do
        expense_report.income_items
      else
        Logger.warning(
          "[QB Expense Sync] upload_and_link_receipts: Income items not loaded, preloading now",
          expense_report_id: expense_report.id
        )

        expense_report
        |> Repo.preload(:income_items)
        |> Map.get(:income_items)
      end

    Logger.info("[QB Expense Sync] upload_and_link_receipts: Items loaded",
      expense_report_id: expense_report.id,
      expense_items_count: length(expense_items),
      income_items_count: length(income_items),
      expense_items_with_receipts:
        Enum.count(expense_items, fn item ->
          item.receipt_s3_path && item.receipt_s3_path != ""
        end),
      income_items_with_evidence:
        Enum.count(income_items, fn item ->
          item.proof_s3_path && item.proof_s3_path != ""
        end)
    )

    # Filter expense items with receipts
    expense_items_with_receipts =
      expense_items
      |> Enum.filter(fn item ->
        item.receipt_s3_path && item.receipt_s3_path != ""
      end)

    # Filter income items with evidence
    income_items_with_evidence =
      income_items
      |> Enum.filter(fn item ->
        item.proof_s3_path && item.proof_s3_path != ""
      end)

    # Combine all files to upload (expense receipts + income evidence)
    all_files_to_upload =
      (expense_items_with_receipts
       |> Enum.map(fn item -> {:expense_receipt, item.receipt_s3_path} end)) ++
        (income_items_with_evidence
         |> Enum.map(fn item -> {:income_evidence, item.proof_s3_path} end))

    Logger.info(
      "[QB Expense Sync] upload_and_link_receipts: Found files to upload",
      expense_report_id: expense_report.id,
      expense_receipts_count: length(expense_items_with_receipts),
      income_evidence_count: length(income_items_with_evidence),
      total_files: length(all_files_to_upload)
    )

    if Enum.empty?(all_files_to_upload) do
      Logger.info(
        "[QB Expense Sync] upload_and_link_receipts: No files to upload",
        expense_report_id: expense_report.id
      )

      {:ok, :no_files}
    else
      # Upload all files (expense receipts and income evidence)
      results =
        all_files_to_upload
        |> Enum.with_index()
        |> Enum.map(fn {{file_type, s3_path}, index} ->
          Logger.info(
            "[QB Expense Sync] upload_and_link_receipts: Processing file #{index + 1}/#{length(all_files_to_upload)} (#{file_type})",
            expense_report_id: expense_report.id,
            s3_path: s3_path,
            file_type: file_type,
            bill_id: bill_id
          )

          upload_receipt_to_quickbooks(s3_path, bill_id)
        end)

      # Check for any errors
      errors = Enum.filter(results, fn r -> match?({:error, _}, r) end)
      successes = Enum.filter(results, fn r -> match?({:ok, _}, r) end)

      Logger.info("[QB Expense Sync] upload_and_link_receipts: Upload results",
        expense_report_id: expense_report.id,
        total_files: length(results),
        successful: length(successes),
        failed: length(errors)
      )

      if Enum.any?(errors) do
        Logger.error(
          "[QB Expense Sync] upload_and_link_receipts: Some files failed to upload",
          expense_report_id: expense_report.id,
          successful_count: length(successes),
          failed_count: length(errors),
          errors: Enum.map(errors, fn {:error, reason} -> inspect(reason) end)
        )

        # Don't fail the entire sync if file upload fails
        # The bill is created, files can be added manually later
        {:ok, :partial_success}
      else
        Logger.info(
          "[QB Expense Sync] upload_and_link_receipts: All files uploaded and linked successfully",
          expense_report_id: expense_report.id,
          files_uploaded: length(successes),
          expense_receipts: length(expense_items_with_receipts),
          income_evidence: length(income_items_with_evidence)
        )

        {:ok, :success}
      end
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp upload_receipt_to_quickbooks(s3_path, bill_id) do
    Logger.info(
      "[QB Expense Sync] upload_receipt_to_quickbooks: Starting receipt upload",
      s3_path: s3_path,
      bill_id: bill_id
    )

    # Download file from S3 to temporary location
    case download_from_s3_to_temp(s3_path) do
      {:ok, temp_file_path} ->
        Logger.info(
          "[QB Expense Sync] upload_receipt_to_quickbooks: File downloaded, uploading to QuickBooks",
          s3_path: s3_path,
          temp_file: temp_file_path,
          bill_id: bill_id,
          file_exists: File.exists?(temp_file_path),
          file_size:
            if(File.exists?(temp_file_path),
              do: File.stat!(temp_file_path).size,
              else: :not_found
            )
        )

        Logger.info(
          "[QB Expense Sync] upload_receipt_to_quickbooks: About to call upload_to_quickbooks",
          temp_file: temp_file_path,
          s3_path: s3_path
        )

        case upload_to_quickbooks(temp_file_path, s3_path) do
          {:ok, attachable_id} ->
            Logger.info(
              "[QB Expense Sync] upload_receipt_to_quickbooks: File uploaded, linking to bill",
              s3_path: s3_path,
              attachable_id: attachable_id,
              bill_id: bill_id
            )

            case link_attachment_to_bill(attachable_id, bill_id) do
              {:ok, _} ->
                # Clean up temp file
                File.rm(temp_file_path)

                Logger.info(
                  "[QB Expense Sync] upload_receipt_to_quickbooks: Successfully uploaded and linked receipt",
                  s3_path: s3_path,
                  attachable_id: attachable_id,
                  bill_id: bill_id
                )

                {:ok, attachable_id}

              {:error, link_error} = error ->
                Logger.error(
                  "[QB Expense Sync] upload_receipt_to_quickbooks: Failed to link attachment to bill",
                  s3_path: s3_path,
                  attachable_id: attachable_id,
                  bill_id: bill_id,
                  error: inspect(link_error)
                )

                # Clean up temp file even on error
                File.rm(temp_file_path)
                error
            end

          {:error, upload_error} = error ->
            Logger.error(
              "[QB Expense Sync] upload_receipt_to_quickbooks: Failed to upload file to QuickBooks",
              s3_path: s3_path,
              temp_file: temp_file_path,
              bill_id: bill_id,
              error: inspect(upload_error)
            )

            # Clean up temp file on error
            File.rm(temp_file_path)
            error
        end

      {:error, reason} = error ->
        Logger.error(
          "[QB Expense Sync] upload_receipt_to_quickbooks: Failed to download file from S3",
          s3_path: s3_path,
          bill_id: bill_id,
          error: inspect(reason)
        )

        error
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp download_from_s3_to_temp(s3_path) do
    # Parse S3 path to get bucket and key
    # S3 paths can be in different formats:
    # - http://bucket.s3.localhost.localstack.cloud:4566/key
    # - https://bucket.fly.storage.tigris.dev/key
    # - /key (relative path)

    bucket = S3Config.expense_reports_bucket_name()
    key = extract_s3_key(s3_path)

    Logger.debug(
      "[QB Expense Sync] download_from_s3_to_temp: Downloading from S3",
      bucket: bucket,
      key: key
    )

    # Verify ExAws is configured with correct credentials
    # ExAws should be configured via runtime.exs to use:
    # - AWS_ACCESS_KEY_ID (from environment)
    # - AWS_SECRET_ACCESS_KEY (from environment)
    # These credentials must have read access to the expense-reports bucket
    access_key_id = Application.get_env(:ex_aws, :access_key_id)

    secret_access_key_configured =
      Application.get_env(:ex_aws, :secret_access_key) != nil

    Logger.debug(
      "[QB Expense Sync] download_from_s3_to_temp: ExAws configuration check",
      bucket: bucket,
      access_key_id_configured: !is_nil(access_key_id),
      secret_access_key_configured: secret_access_key_configured
    )

    # Create temp file
    temp_file =
      System.tmp_dir!()
      |> Path.join("qb_upload_#{:rand.uniform(1_000_000_000)}")

    # Download from S3 using ExAws
    # ExAws will use credentials configured in runtime.exs:
    # config :ex_aws,
    #   access_key_id: {:system, "AWS_ACCESS_KEY_ID"},
    #   secret_access_key: {:system, "AWS_SECRET_ACCESS_KEY"}
    case ExAws.S3.get_object(bucket, key) |> ExAws.request() do
      {:ok, %{body: body}} ->
        File.write!(temp_file, body)

        Logger.debug(
          "[QB Expense Sync] download_from_s3_to_temp: Successfully downloaded file",
          bucket: bucket,
          key: key,
          file_size: byte_size(body),
          temp_file: temp_file
        )

        {:ok, temp_file}

      {:error, reason} ->
        Logger.error(
          "[QB Expense Sync] download_from_s3_to_temp: Failed to download from S3",
          bucket: bucket,
          key: key,
          error: inspect(reason),
          access_key_id_configured: !is_nil(access_key_id),
          secret_access_key_configured: secret_access_key_configured,
          error_hint:
            if match?({:error, %{code: :access_denied}}, reason) do
              "Check that AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY have read permissions for bucket: #{bucket}"
            else
              nil
            end
        )

        {:error, :s3_download_failed}
    end
  end

  defp extract_s3_key(s3_path) do
    # Remove protocol and domain, extract key
    # Also remove bucket name if it's included in the path
    bucket_name = S3Config.expense_reports_bucket_name()

    s3_path
    |> String.replace(~r/^https?:\/\/[^\/]+/, "")
    |> String.trim_leading("/")
    |> String.replace(~r/^#{Regex.escape(bucket_name)}\//, "")
  end

  defp upload_to_quickbooks(file_path, original_s3_path) do
    try do
      Logger.info(
        "[QB Expense Sync] upload_to_quickbooks: Starting upload process",
        file_path: file_path,
        original_s3_path: original_s3_path,
        file_exists: File.exists?(file_path)
      )

      # Get base filename without extension
      base_name = Path.basename(original_s3_path) |> Path.rootname()

      Logger.info(
        "[QB Expense Sync] upload_to_quickbooks: Detecting file type",
        file_path: file_path,
        base_name: base_name
      )

      # Detect file type from magic bytes (most reliable method)
      {detected_ext, content_type} = detect_file_type_from_content(file_path)

      Logger.info(
        "[QB Expense Sync] upload_to_quickbooks: File type detected",
        detected_ext: detected_ext,
        content_type: content_type
      )

      # Always ensure the filename has an extension for QuickBooks
      file_name = "#{base_name}#{detected_ext}"

      file_exists = File.exists?(file_path)

      file_size =
        if file_exists, do: File.stat!(file_path).size, else: :not_found

      Logger.info(
        "[QB Expense Sync] upload_to_quickbooks: Uploading file to QuickBooks",
        file_name: file_name,
        extension: detected_ext,
        content_type: content_type,
        file_path: file_path,
        file_exists: file_exists,
        file_size: file_size
      )

      if file_exists do
        Logger.info(
          "[QB Expense Sync] upload_to_quickbooks: Calling client_module().upload_attachment",
          file_path: file_path,
          file_name: file_name,
          content_type: content_type
        )

        result =
          client_module().upload_attachment(file_path, file_name, content_type)

        case result do
          {:ok, attachable_id} ->
            Logger.info(
              "[QB Expense Sync] upload_to_quickbooks: Successfully uploaded to QuickBooks",
              file_name: file_name,
              attachable_id: attachable_id
            )

          {:error, error} ->
            Logger.error(
              "[QB Expense Sync] upload_to_quickbooks: Failed to upload to QuickBooks",
              file_name: file_name,
              error: inspect(error),
              error_type: if(is_atom(error), do: error, else: :unknown)
            )
        end

        result
      end
    rescue
      e ->
        exception_message = Exception.message(e)
        exception_type = e.__struct__
        stacktrace = Exception.format_stacktrace(__STACKTRACE__)

        # Log exception details in the message itself for better visibility
        Logger.error(
          "[QB Expense Sync] upload_to_quickbooks: Exception during upload - #{exception_type}: #{exception_message}\nFile: #{file_path}\nOriginal S3 path: #{original_s3_path}\n\nStacktrace:\n#{stacktrace}",
          file_path: file_path,
          original_s3_path: original_s3_path,
          exception_type: inspect(exception_type),
          exception_message: exception_message,
          exception: inspect(e, limit: :infinity),
          stacktrace: stacktrace
        )

        {:error,
         "Exception during upload: #{exception_type}: #{exception_message}"}
    catch
      :exit, reason ->
        Logger.error(
          "[QB Expense Sync] upload_to_quickbooks: Process exited during upload",
          file_path: file_path,
          reason: inspect(reason)
        )

        {:error, "Process exited: #{inspect(reason)}"}

      :throw, reason ->
        Logger.error(
          "[QB Expense Sync] upload_to_quickbooks: Exception thrown during upload",
          file_path: file_path,
          reason: inspect(reason)
        )

        {:error, "Exception thrown: #{inspect(reason)}"}
    end
  end

  # Detect file type from file content (magic bytes) using the file_type library
  # Returns {extension, content_type} tuple
  defp detect_file_type_from_content(file_path) do
    case FileType.from_path(file_path) do
      {:ok, {ext, mime_type}} ->
        # FileType returns extension without dot, add it
        extension = if String.starts_with?(ext, "."), do: ext, else: ".#{ext}"
        {extension, mime_type}

      {:error, reason} ->
        Logger.warning(
          "[QB Expense Sync] detect_file_type_from_content: Failed to detect file type, defaulting to PDF",
          file_path: file_path,
          error: inspect(reason)
        )

        # Default to PDF for receipts (most common receipt format)
        {".pdf", "application/pdf"}
    end
  rescue
    e ->
      Logger.error(
        "[QB Expense Sync] detect_file_type_from_content: Exception while detecting file type, defaulting to PDF",
        file_path: file_path,
        exception: "#{e.__struct__}: #{Exception.message(e)}"
      )

      # Default to PDF for receipts
      {".pdf", "application/pdf"}
  end

  defp link_attachment_to_bill(attachable_id, bill_id) do
    client_module().link_attachment_to_bill(attachable_id, bill_id)
  end

  defp update_sync_attempt_timestamp(%ExpenseReport{} = expense_report) do
    now = DateTime.utc_now()

    expense_report
    |> ExpenseReport.changeset(%{quickbooks_last_sync_attempt_at: now})
    |> Repo.update()
  end

  # Store bill_id and vendor_id immediately after bill creation (for idempotency)
  # This prevents duplicate bills if the sync is retried before receipts are uploaded
  defp update_expense_report_with_bill_id(
         %ExpenseReport{} = expense_report,
         vendor_id,
         bill_id
       ) do
    expense_report
    |> ExpenseReport.changeset(%{
      quickbooks_vendor_id: vendor_id,
      quickbooks_bill_id: bill_id
    })
    |> Repo.update()
  end

  defp update_expense_report_success(
         %ExpenseReport{} = expense_report,
         vendor_id,
         bill_id
       ) do
    now = DateTime.utc_now()

    expense_report
    |> ExpenseReport.changeset(%{
      quickbooks_vendor_id: vendor_id,
      quickbooks_bill_id: bill_id,
      quickbooks_sync_status: "synced",
      quickbooks_sync_error: nil,
      quickbooks_synced_at: now
    })
    |> Repo.update()
  end

  defp update_expense_report_error(%ExpenseReport{} = expense_report, error) do
    error_message = if is_binary(error), do: error, else: inspect(error)

    Logger.debug(
      "[QB Expense Sync] update_expense_report_error: Updating expense report with error",
      expense_report_id: expense_report.id,
      error: error_message
    )

    case expense_report
         |> ExpenseReport.changeset(%{
           quickbooks_sync_status: "failed",
           quickbooks_sync_error: error_message
         })
         |> Repo.update() do
      {:ok, updated} ->
        Logger.debug(
          "[QB Expense Sync] update_expense_report_error: Successfully updated",
          expense_report_id: updated.id,
          sync_status: updated.quickbooks_sync_status
        )

        {:ok, updated}

      {:error, changeset} ->
        Logger.error(
          "[QB Expense Sync] update_expense_report_error: Failed to update expense report",
          expense_report_id: expense_report.id,
          errors: inspect(changeset.errors)
        )

        {:error, changeset}
    end
  end
end
