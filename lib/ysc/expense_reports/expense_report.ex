defmodule Ysc.ExpenseReports.ExpenseReport do
  @moduledoc """
  Expense report schema.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

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

  @user_submittable_fields [
    :user_id,
    :purpose,
    :reimbursement_method,
    :status,
    :address_id,
    :bank_account_id,
    :event_id,
    :certification_accepted
  ]

  @internal_fields [
    :quickbooks_bill_id,
    :quickbooks_vendor_id,
    :quickbooks_sync_status,
    :quickbooks_sync_error,
    :quickbooks_synced_at,
    :quickbooks_last_sync_attempt_at
  ]

  @all_statuses ["draft", "submitted", "approved", "rejected", "paid"]
  @user_submittable_statuses ["draft", "submitted"]

  @doc """
  Changeset for member-submitted expense reports (create / resubmit).

  Does not accept QuickBooks sync fields or privileged status values.
  """
  def submission_changeset(expense_report, attrs, opts \\ []) do
    attrs = normalize_event_id_in_attrs(attrs)

    expense_report
    |> cast(attrs, @user_submittable_fields)
    |> validate_required([:user_id, :purpose, :reimbursement_method])
    |> validate_inclusion(:reimbursement_method, ["check", "bank_transfer"])
    |> validate_inclusion(:status, @user_submittable_statuses)
    |> validate_reimbursement_method(opts)
    |> cast_assoc(:expense_items, with: &ExpenseReportItem.changeset/2)
    |> cast_assoc(:income_items, with: &ExpenseReportIncomeItem.changeset/2)
    |> validate_all_expense_items_have_receipts()
    |> validate_certification_accepted()
  end

  @doc """
  Changeset for an autosaved `draft` expense report.

  Only `:user_id` is required; `:purpose` and `:reimbursement_method` may be
  blank while the member is still filling the form in. `:status` is forced to
  `"draft"` and none of the submission gates (receipts, certification) run.
  Line items go through the lenient `draft_changeset/2` variants so
  half-typed rows persist.
  """
  def draft_changeset(expense_report, attrs, _opts \\ []) do
    attrs = normalize_event_id_in_attrs(attrs)

    expense_report
    |> cast(attrs, @user_submittable_fields)
    |> put_change(:status, "draft")
    |> validate_required([:user_id])
    |> validate_draft_reimbursement_method()
    |> cast_assoc(:expense_items, with: &ExpenseReportItem.draft_changeset/2)
    |> cast_assoc(:income_items,
      with: &ExpenseReportIncomeItem.draft_changeset/2
    )
    # One active draft per user (partial unique index). `save_draft/3` catches
    # this and retries against the existing draft.
    |> unique_constraint(:user_id, name: :expense_reports_user_draft_idx)
  end

  @doc """
  Changeset for admin/system status updates.

  Only casts `:status` and `:quickbooks_sync_error` - it deliberately skips
  `cast_assoc/2` and the expense-item validations in `changeset/3`, since a
  status-only transition (e.g. an automatic "paid" or "rejected" flip driven
  by a QuickBooks webhook) shouldn't fail because of unrelated expense-item
  data issues.
  """
  def status_changeset(expense_report, attrs) do
    expense_report
    |> cast(attrs, [:status, :quickbooks_sync_error])
    |> validate_required([:status])
    |> validate_inclusion(:status, @all_statuses)
  end

  @doc """
  Internal changeset for QuickBooks sync and other system updates.
  """
  def changeset(expense_report, attrs, opts \\ []) do
    attrs = normalize_event_id_in_attrs(attrs)

    expense_report
    |> cast(attrs, @user_submittable_fields ++ @internal_fields)
    |> validate_required([:user_id, :purpose, :reimbursement_method])
    |> validate_inclusion(:reimbursement_method, ["check", "bank_transfer"])
    |> validate_inclusion(:status, @all_statuses)
    |> validate_reimbursement_method(opts)
    |> cast_assoc(:expense_items, with: &ExpenseReportItem.changeset/2)
    |> cast_assoc(:income_items, with: &ExpenseReportIncomeItem.changeset/2)
    |> validate_all_expense_items_have_receipts()
    |> validate_certification_accepted()
  end

  # A draft may not have picked a reimbursement method yet; only validate the
  # value once one is actually set.
  defp validate_draft_reimbursement_method(changeset) do
    case Ecto.Changeset.get_field(changeset, :reimbursement_method) do
      nil ->
        changeset

      "" ->
        Ecto.Changeset.put_change(changeset, :reimbursement_method, nil)

      _ ->
        validate_inclusion(changeset, :reimbursement_method, [
          "check",
          "bank_transfer"
        ])
    end
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
          # Mileage items are backed by the logged date/route/purpose/miles
          # instead of a receipt, per the IRS Accountable Plan rules.
          receipt_path = get_receipt_path(item)

          get_expense_type(item) != "mileage" &&
            (is_nil(receipt_path) || receipt_path == "")
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

  defp get_expense_type(%Ecto.Changeset{} = item) do
    Ecto.Changeset.get_field(item, :expense_type)
  end

  defp get_expense_type(%ExpenseReportItem{} = item) do
    item.expense_type
  end

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
