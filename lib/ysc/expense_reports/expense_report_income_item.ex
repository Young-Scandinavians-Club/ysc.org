defmodule Ysc.ExpenseReports.ExpenseReportIncomeItem do
  @moduledoc """
  Expense report income item schema.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ysc.ExpenseReports.ExpenseReport

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "expense_report_income_items" do
    belongs_to :expense_report, ExpenseReport,
      foreign_key: :expense_report_id,
      references: :id

    field :date, :date
    field :description, :string
    field :amount, Money.Ecto.Composite.Type, default_currency: :USD
    field :proof_s3_path, :string

    timestamps()
  end

  @doc """
  Creates a changeset for an expense report income item.
  """
  def changeset(expense_report_income_item, attrs) do
    expense_report_income_item
    |> cast(attrs, [
      :expense_report_id,
      :date,
      :description,
      :amount,
      :proof_s3_path
    ])
    |> prepare_changes(&parse_money_fields/1)
    # expense_report_id is not required when creating through parent association (cast_assoc)
    # It will be automatically set when the parent expense_report is inserted
    # proof_s3_path is optional (income items don't require attachments)
    |> validate_required([:date, :description, :amount])
    |> validate_length(:description, max: 1000)
    |> validate_money(:amount)
    |> validate_length(:proof_s3_path, max: 2048)
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
