defmodule Ysc.ExpenseReports.ExpenseReportItem do
  @moduledoc """
  Expense report item schema.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ysc.ExpenseReports.ExpenseReport

  @expense_types ["purchase", "mileage"]

  # The club's per-mile reimbursement rate. Update this constant to change the
  # rate applied to every mileage expense item going forward.
  @mileage_rate Money.new(:USD, "0.30")

  # Hard cap per mileage line item. Mileage needs no receipt, so an unbounded
  # miles_driven field would let a member create an arbitrarily large
  # QuickBooks bill on submit.
  @max_miles_driven 10_000

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "expense_report_items" do
    belongs_to :expense_report, ExpenseReport,
      foreign_key: :expense_report_id,
      references: :id

    field :date, :date
    field :expense_type, :string, default: "purchase"
    field :vendor, :string
    field :description, :string
    field :amount, Money.Ecto.Composite.Type, default_currency: :USD
    field :receipt_s3_path, :string

    # Mileage-only fields, kept to satisfy the IRS "Accountable Plan" record-keeping
    # requirements: date (above), destination, business purpose (via :description),
    # and mileage for the trip.
    field :miles_driven, :integer
    field :mileage_from_to, :string

    timestamps()
  end

  @doc """
  The reimbursement rate applied to mileage expense items.
  """
  def mileage_rate, do: @mileage_rate

  @doc """
  Creates a changeset for an expense report item.
  """
  def changeset(expense_report_item, attrs) do
    expense_report_item
    |> cast(attrs, [
      :expense_report_id,
      :date,
      :expense_type,
      :vendor,
      :description,
      :amount,
      :receipt_s3_path,
      :miles_driven,
      :mileage_from_to
    ])
    |> prepare_changes(&parse_money_fields/1)
    |> validate_inclusion(:expense_type, @expense_types)
    |> apply_mileage_fields()
    # expense_report_id is not required when creating through parent association (cast_assoc)
    # It will be automatically set when the parent expense_report is inserted
    |> validate_required([:date, :vendor, :description, :amount])
    |> validate_length(:vendor, max: 255)
    |> validate_length(:description, max: 1000)
    |> validate_money(:amount)
    |> validate_length(:receipt_s3_path, max: 2048)
    |> validate_mileage_fields()
  end

  # For mileage items, the vendor and reimbursement amount aren't user input -
  # they're derived from the mileage rate so they can't drift out of sync with
  # miles driven. This runs on every changeset build (not just on persist) so the
  # reimbursement amount updates live as the member types in the form.
  defp apply_mileage_fields(changeset) do
    if get_field(changeset, :expense_type) == "mileage" do
      miles = get_field(changeset, :miles_driven)

      changeset
      |> put_change(:vendor, "Mileage")
      |> put_change(:amount, calculate_mileage_amount(miles))
    else
      changeset
    end
  end

  defp calculate_mileage_amount(miles) when is_integer(miles) and miles > 0 do
    {:ok, amount} = Money.mult(@mileage_rate, miles)
    amount
  end

  defp calculate_mileage_amount(_miles), do: Money.new(0, :USD)

  # Mirrors the IRS Accountable Plan requirements for a mileage log: in
  # addition to the date and business purpose (:description, required above),
  # a mileage item needs a destination and a mileage figure for the trip.
  defp validate_mileage_fields(changeset) do
    if get_field(changeset, :expense_type) == "mileage" do
      changeset
      |> validate_required([:miles_driven, :mileage_from_to])
      |> validate_number(:miles_driven,
        greater_than: 0,
        less_than_or_equal_to: @max_miles_driven
      )
      |> validate_length(:mileage_from_to, max: 255)
    else
      changeset
    end
  end

  defp parse_money_fields(changeset) do
    changeset
    |> update_change(:amount, fn
      value when is_binary(value) -> Ysc.MoneyHelper.parse_money(value)
      value -> value
    end)
  end

  # Custom validation for money field
  defp validate_money(changeset, field) do
    validate_change(changeset, field, fn _field, value ->
      case value do
        %Money{currency: :USD} = money when money.amount > 0 ->
          []

        %Money{currency: currency} when currency != :USD ->
          [{field, "must be in USD"}]

        %Money{amount: amount} when amount <= 0 ->
          [{field, "must be greater than 0"}]

        nil ->
          []

        _ ->
          [{field, "invalid money format"}]
      end
    end)
  end
end
