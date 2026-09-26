defmodule YscWeb.Emails.ExpenseReportHelpers do
  @moduledoc """
  Shared loading and display formatting for expense-report emails.

  Member confirmation and treasurer notification emails render the same
  report payload (totals, line items, reimbursement method, event, and
  bank account). Call `email_payload/2` and add only the fields unique
  to that template.

  ## Examples

      {report, fields} =
        email_payload(expense_report,
          missing: "Not specified",
          bank_missing: "Not on file"
        )

      %{
        first_name: member_greeting_name(report.user),
        expense_report: fields,
        expense_report_url: member_url(report.id)
      }
  """

  import YscWeb.Emails.Helpers,
    only: [
      absolute_url: 1,
      format_date: 1,
      format_datetime: 1,
      format_money: 1
    ]

  alias Ysc.ExpenseReports.ExpenseReport
  alias Ysc.Repo

  @preloads [
    :user,
    :expense_items,
    :income_items,
    :event,
    :bank_account,
    :address
  ]

  @doc """
  Loads required associations and returns `{report, fields}` for MJML.

  `fields` is the `expense_report` assign passed to both confirmation and
  treasurer templates.

  Options:

    * `:missing` — fallback for blank purpose, vendor, and description.
      Defaults to `"Not specified"`.
    * `:bank_missing` — fallback for a missing account last-4. Defaults
      to `:missing`.
    * `:include_address` — when true, include mailing address (treasurer
      notifications). Defaults to `false`.
  """
  def email_payload(expense_report, opts \\ []) do
    missing = Keyword.get(opts, :missing, "Not specified")
    bank_missing = Keyword.get(opts, :bank_missing, missing)
    include_address? = Keyword.get(opts, :include_address, false)
    report = load!(expense_report)

    expense_items_list = report.expense_items || []
    income_items_list = report.income_items || []

    expense_total = sum_item_amounts(expense_items_list)
    income_total = sum_item_amounts(income_items_list)
    net_total = money_sub_or_zero(expense_total, income_total)

    fields = %{
      id: report.id,
      purpose: present_or(report.purpose, missing),
      submitted_date: format_datetime(report.inserted_at),
      reimbursement_method:
        reimbursement_method_label(report.reimbursement_method),
      expense_total: format_money(expense_total),
      income_total: format_money(income_total),
      net_total: format_money(net_total),
      expense_items: format_expense_items(expense_items_list, missing),
      income_items: format_income_items(income_items_list, missing),
      event: event_info(loaded_assoc(report, :event)),
      bank_account:
        bank_account_info(loaded_assoc(report, :bank_account), bank_missing)
    }

    fields =
      if include_address? do
        Map.put(fields, :address, address_info(loaded_assoc(report, :address)))
      else
        fields
      end

    {report, fields}
  end

  @doc """
  Reloads the report with email associations when they are not loaded.

  Raises `ArgumentError` when the report is nil, has no id, cannot be
  found, or has no user.
  """
  def load!(nil), do: raise(ArgumentError, "Expense report cannot be nil")

  def load!(%ExpenseReport{id: nil} = report) do
    raise ArgumentError, "Expense report missing id: #{inspect(report)}"
  end

  def load!(%ExpenseReport{} = report) do
    report = ensure_preloaded(report)

    if is_nil(report.user) do
      raise ArgumentError,
            "Expense report missing user association: #{report.id}"
    end

    report
  end

  @doc """
  Member-facing reimbursement method label (`"Bank Transfer"`, `"Check"`).
  """
  def reimbursement_method_label("bank_transfer"), do: "Bank Transfer"
  def reimbursement_method_label("check"), do: "Check"

  def reimbursement_method_label(method) when is_binary(method),
    do: String.capitalize(method)

  def reimbursement_method_label(_), do: "Not specified"

  @doc """
  Absolute URL for the member expense-report success page.
  """
  def member_url(expense_report_id),
    do: absolute_url("/expensereport/#{expense_report_id}/success")

  @doc """
  Absolute URL for the admin expense-report page.
  """
  def admin_url(expense_report_id),
    do: absolute_url("/admin/expense_reports/#{expense_report_id}")

  @doc """
  Display name and email for treasurer notifications.
  """
  def user_info(user) do
    %{
      name:
        "#{user.first_name || ""} #{user.last_name || ""}"
        |> String.trim(),
      email: user.email
    }
  end

  @doc """
  Returns the trimmed string, or `fallback` when the value is blank.
  """
  def present_or(value, fallback) when is_binary(value) do
    case String.trim(value) do
      "" -> fallback
      trimmed -> trimmed
    end
  end

  def present_or(_value, fallback), do: fallback

  defp ensure_preloaded(report) do
    if Ecto.assoc_loaded?(report.user) &&
         Ecto.assoc_loaded?(report.expense_items) &&
         Ecto.assoc_loaded?(report.income_items) do
      report
    else
      load_with_preloads(report.id)
    end
  end

  defp load_with_preloads(expense_report_id) do
    case Repo.get(ExpenseReport, expense_report_id)
         |> Repo.preload(@preloads) do
      nil ->
        raise ArgumentError, "Expense report not found: #{expense_report_id}"

      loaded_report ->
        loaded_report
    end
  end

  defp sum_item_amounts(items) do
    Enum.reduce(items, Money.new(0, :USD), fn item, acc ->
      add_item_amount(acc, item.amount)
    end)
  end

  defp add_item_amount(acc, amount) do
    if amount do
      case Money.add(acc, amount) do
        {:ok, new_total} -> new_total
        {:error, _} -> acc
      end
    else
      acc
    end
  end

  defp money_sub_or_zero(expense_total, income_total) do
    case Money.sub(expense_total, income_total) do
      {:ok, result} -> result
      {:error, _} -> Money.new(0, :USD)
    end
  end

  defp format_expense_items(expense_items_list, missing) do
    Enum.map(expense_items_list, fn item ->
      %{
        vendor: present_or(item.vendor, missing),
        description: present_or(item.description, missing),
        date: format_date(item.date),
        amount: format_money(item.amount),
        has_receipt: attached?(item.receipt_s3_path),
        mileage: item.expense_type == "mileage",
        mileage_info: format_mileage_info(item)
      }
    end)
  end

  defp format_mileage_info(%{expense_type: "mileage"} = item) do
    route = if item.mileage_from_to, do: "#{item.mileage_from_to} — ", else: ""
    miles = if item.miles_driven, do: "#{item.miles_driven} mi", else: ""
    "#{route}#{miles}"
  end

  defp format_mileage_info(_item), do: nil

  defp format_income_items(income_items_list, missing) do
    Enum.map(income_items_list, fn item ->
      %{
        description: present_or(item.description, missing),
        date: format_date(item.date),
        amount: format_money(item.amount),
        has_proof: attached?(item.proof_s3_path)
      }
    end)
  end

  defp event_info(nil), do: nil

  defp event_info(event) do
    %{
      title: event.title,
      id: event.id,
      reference_id: event.reference_id
    }
  end

  defp bank_account_info(nil, _missing), do: nil

  defp bank_account_info(bank_account, missing) do
    %{
      last_4: present_or(bank_account.account_number_last_4, missing)
    }
  end

  defp address_info(nil), do: nil

  defp address_info(address) do
    %{
      address: address.address,
      city: address.city,
      region: address.region,
      postal_code: address.postal_code,
      country: address.country
    }
  end

  defp attached?(path) when is_binary(path) and path != "", do: true
  defp attached?(_), do: false

  defp loaded_assoc(report, field) do
    value = Map.fetch!(report, field)

    if Ecto.assoc_loaded?(value) do
      value
    else
      nil
    end
  end
end
