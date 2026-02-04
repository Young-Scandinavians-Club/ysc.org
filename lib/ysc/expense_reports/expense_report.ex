defmodule Ysc.ExpenseReports.ExpenseReport do
  @moduledoc """
  Expense report schema.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ysc.Accounts.{User, Address}

  alias Ysc.ExpenseReports.{
    BankAccount,
    ExpenseReportItem,
    ExpenseReportIncomeItem
  }

  alias Ysc.Events.Event

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "expense_reports" do
    belongs_to :user, User, foreign_key: :user_id, references: :id

    field :purpose, :string
    field :reimbursement_method, :string
    field :status, :string, default: "draft"
    field :certification_accepted, :boolean, default: false

    # QuickBooks sync fields
    field :quickbooks_bill_id, :string
    field :quickbooks_vendor_id, :string
    field :quickbooks_sync_status, :string, default: "pending"
    field :quickbooks_sync_error, :string
    field :quickbooks_synced_at, :utc_datetime
    field :quickbooks_last_sync_attempt_at, :utc_datetime

    belongs_to :address, Address, foreign_key: :address_id, references: :id

    belongs_to :bank_account, BankAccount,
      foreign_key: :bank_account_id,
      references: :id

    belongs_to :event, Event, foreign_key: :event_id, references: :id

    has_many :expense_items, ExpenseReportItem, foreign_key: :expense_report_id

    has_many :income_items, ExpenseReportIncomeItem,
      foreign_key: :expense_report_id

    timestamps()
  end

  @doc """
  Creates a changeset for an expense report.
  """
  def changeset(expense_report, attrs, opts \\ []) do
    # Normalize empty string to nil for event_id before casting
    attrs = normalize_event_id_in_attrs(attrs)

    expense_report
    |> cast(attrs, [
      :user_id,
      :purpose,
      :reimbursement_method,
      :status,
      :address_id,
      :bank_account_id,
      :event_id,
      :certification_accepted,
      :quickbooks_bill_id,
      :quickbooks_vendor_id,
      :quickbooks_sync_status,
      :quickbooks_sync_error,
      :quickbooks_synced_at,
      :quickbooks_last_sync_attempt_at
    ])
    |> validate_required([:user_id, :purpose, :reimbursement_method])
    |> validate_inclusion(:reimbursement_method, ["check", "bank_transfer"])
    |> validate_inclusion(:status, [
      "draft",
      "submitted",
      "approved",
      "rejected",
      "paid"
    ])
    |> validate_reimbursement_method(opts)
    |> cast_assoc(:expense_items, with: &ExpenseReportItem.changeset/2)
    |> cast_assoc(:income_items, with: &ExpenseReportIncomeItem.changeset/2)
    |> validate_all_expense_items_have_receipts()
    |> validate_certification_accepted()
  end

  # Normalize empty string to nil for event_id in attrs before casting
  # This prevents validation errors when the select dropdown sends "" instead of nil
  defp normalize_event_id_in_attrs(attrs) when is_map(attrs) do
    # Check both string and atom keys, but only normalize the key type that exists
    event_id_string = Map.get(attrs, "event_id")
    event_id_atom = Map.get(attrs, :event_id)
    event_id_value = event_id_string || event_id_atom

    if event_id_value == "" do
      # Only set the key type that already exists, or default to string if neither exists
      cond do
        Map.has_key?(attrs, "event_id") ->
          Map.put(attrs, "event_id", nil)

        Map.has_key?(attrs, :event_id) ->
          Map.put(attrs, :event_id, nil)

        true ->
          Map.put(attrs, "event_id", nil)
      end
    else
      attrs
    end
  end

  defp normalize_event_id_in_attrs(attrs), do: attrs

  defp validate_all_expense_items_have_receipts(changeset) do
    expense_items = Ecto.Changeset.get_field(changeset, :expense_items, [])

    # Only validate if status is "submitted" (not for drafts)
    status = Ecto.Changeset.get_field(changeset, :status)

    if status == "submitted" do
      items_without_receipts =
        expense_items
        |> Enum.with_index()
        |> Enum.filter(fn {item, _index} ->
          receipt_path = get_receipt_path(item)
          is_nil(receipt_path) || receipt_path == ""
        end)

      if Enum.any?(items_without_receipts) do
        changeset
        |> add_error(
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

  defp get_receipt_path(%Ecto.Changeset{} = item) do
    Ecto.Changeset.get_field(item, :receipt_s3_path)
  end

  defp get_receipt_path(%ExpenseReportItem{} = item) do
    item.receipt_s3_path
  end

  defp get_receipt_path(_), do: nil

  defp validate_reimbursement_method(changeset, _opts) do
    # This validation is handled in the context module's validate_reimbursement_setup
    # to have access to the full user struct. This is kept for basic validation.
    changeset
  end

  defp validate_certification_accepted(changeset) do
    status = Ecto.Changeset.get_field(changeset, :status)

    certification_accepted =
      Ecto.Changeset.get_field(changeset, :certification_accepted)

    if status == "submitted" && !certification_accepted do
      changeset
      |> add_error(
        :certification_accepted,
        "You must accept the certification to submit"
      )
    else
      changeset
    end
  end
end
