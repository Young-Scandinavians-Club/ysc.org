defmodule YscWeb.Workers.QuickbooksSyncJobTest do
  use Ysc.DataCase, async: false

  alias Ysc.Ledgers.Payment
  alias YscWeb.Workers.QuickbooksSyncJob

  defp classify_opts(extra \\ []) do
    Keyword.merge(
      [
        entity: "payment",
        id_key: :payment_id,
        id: "pay_1",
        not_found: :payment_not_found,
        success_id_key: :sales_receipt_id,
        non_retriable: [:payment_not_found, :no_income_account_for_item]
      ],
      extra
    )
  end

  describe "cast_id/1" do
    test "returns a valid ULID unchanged" do
      id = Ecto.ULID.generate()
      assert QuickbooksSyncJob.cast_id(id) == id
    end

    test "returns non-ULID values unchanged" do
      assert QuickbooksSyncJob.cast_id("not-a-ulid") == "not-a-ulid"
    end
  end

  describe "lock_not_available?/1" do
    test "is true for FOR UPDATE NOWAIT contention" do
      error = %Postgrex.Error{
        postgres: %{
          code: :lock_not_available,
          message: "could not obtain lock on row"
        }
      }

      assert QuickbooksSyncJob.lock_not_available?(error)
    end

    test "is false for other Postgrex errors and non-errors" do
      other = %Postgrex.Error{
        postgres: %{code: :unique_violation, message: "duplicate"}
      }

      refute QuickbooksSyncJob.lock_not_available?(other)
      refute QuickbooksSyncJob.lock_not_available?(:lock_not_available)
    end
  end

  describe "validation_fault?/1" do
    test "detects QuickBooks validation fault strings" do
      assert QuickbooksSyncJob.validation_fault?("ValidationFault: bad field")

      assert QuickbooksSyncJob.validation_fault?(
               "Request has invalid or unsupported property"
             )

      assert QuickbooksSyncJob.validation_fault?("2010: detail")
    end

    test "is false for other errors" do
      refute QuickbooksSyncJob.validation_fault?("QuickBooks API unavailable")
      refute QuickbooksSyncJob.validation_fault?(:timeout)
    end
  end

  describe "synced_sales_receipt_id/1" do
    test "returns the sales receipt id when already synced" do
      assert QuickbooksSyncJob.synced_sales_receipt_id(%{
               quickbooks_sync_status: "synced",
               quickbooks_sales_receipt_id: "sr_123"
             }) == "sr_123"
    end

    test "returns nil when not synced or the id is missing" do
      assert QuickbooksSyncJob.synced_sales_receipt_id(%{
               quickbooks_sync_status: "pending",
               quickbooks_sales_receipt_id: "sr_123"
             }) == nil

      assert QuickbooksSyncJob.synced_sales_receipt_id(%{
               quickbooks_sync_status: "synced",
               quickbooks_sales_receipt_id: nil
             }) == nil
    end
  end

  describe "classify_error/2" do
    test "discards configured non-retriable atoms" do
      assert QuickbooksSyncJob.classify_error(
               :no_income_account_for_item,
               classify_opts()
             ) == {:discard, :no_income_account_for_item}
    end

    test "discards QuickBooks validation fault strings" do
      reason =
        "ValidationFault: Request has invalid or unsupported property (2010: detail)"

      assert QuickbooksSyncJob.classify_error(reason, classify_opts()) ==
               {:discard, reason}
    end

    test "retries other binary errors" do
      assert QuickbooksSyncJob.classify_error(
               "QuickBooks API unavailable",
               classify_opts()
             ) == {:error, "QuickBooks API unavailable"}
    end

    test "retries other non-binary errors" do
      assert QuickbooksSyncJob.classify_error(:timeout, classify_opts()) ==
               {:error, :timeout}
    end
  end

  describe "handle_lock_error/2" do
    test "returns :ok when the row is locked by another process" do
      error = %Postgrex.Error{
        postgres: %{
          code: :lock_not_available,
          message: "could not obtain lock on row"
        }
      }

      assert :ok = QuickbooksSyncJob.handle_lock_error(error, classify_opts())
    end

    test "asks the caller to reraise other Postgrex errors" do
      error = %Postgrex.Error{
        postgres: %{code: :unique_violation, message: "duplicate"}
      }

      assert {:reraise, ^error} =
               QuickbooksSyncJob.handle_lock_error(error, classify_opts())
    end
  end

  describe "lock_and_sync/2" do
    test "discards when the locked row is missing" do
      assert {:discard, :payment_not_found} =
               QuickbooksSyncJob.lock_and_sync(
                 [
                   schema: Payment,
                   id: Ecto.ULID.generate(),
                   entity: "payment",
                   id_key: :payment_id,
                   not_found: :payment_not_found,
                   non_retriable: [:payment_not_found],
                   success_id_key: :sales_receipt_id
                 ],
                 fn _record -> flunk("sync must not run for a missing row") end
               )
    end
  end

  describe "ci_query_explain_query/0" do
    test "returns the FOR UPDATE NOWAIT row lock query" do
      query = QuickbooksSyncJob.ci_query_explain_query()

      assert %Ecto.Query{} = query
      assert query.lock == "FOR UPDATE NOWAIT"
    end
  end
end
