defmodule YscWeb.Emails.ExpenseReportTreasurerNotification do
  @moduledoc """
  Email template for expense report submission notification to Treasurer.

  Sends an internal notification email to the Treasurer when a new expense report is submitted.
  """
  use MjmlEEx,
    mjml_template: "templates/expense_report_treasurer_notification.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  alias Ysc.Repo
  alias Ysc.ExpenseReports.ExpenseReport

  def get_template_name() do
    "expense_report_treasurer_notification"
  end

  def get_subject() do
    "New Expense Report Submitted - Action Required"
  end

  @doc """
  Prepares expense report treasurer notification email data.

  ## Parameters:
  - `expense_report`: The submitted expense report with preloaded associations

  ## Returns:
  - Map with all necessary data for the email template
  """
  def prepare_email_data(expense_report) do
    expense_report = validate_and_preload_expense_report(expense_report)

    submitted_date = format_datetime(expense_report.inserted_at)
    expense_items_list = expense_report.expense_items || []
    income_items_list = expense_report.income_items || []

    expense_total = calculate_expense_total(expense_items_list)
    income_total = calculate_income_total(income_items_list)
    net_total = calculate_net_total(expense_total, income_total)

    expense_items = format_expense_items(expense_items_list)
    income_items = format_income_items(income_items_list)

    reimbursement_method =
      format_reimbursement_method(expense_report.reimbursement_method)

    user_info = build_user_info(expense_report.user)
    event_info = build_event_info(expense_report.event)
    bank_account_info = build_bank_account_info(expense_report.bank_account)
    address_info = build_address_info(expense_report.address)

    %{
      expense_report: %{
        id: expense_report.id,
        purpose: expense_report.purpose || "N/A",
        submitted_date: submitted_date,
        reimbursement_method: reimbursement_method,
        expense_total: format_money(expense_total),
        income_total: format_money(income_total),
        net_total: format_money(net_total),
        expense_items: expense_items,
        income_items: income_items,
        event: event_info,
        bank_account: bank_account_info,
        address: address_info
      },
      user: user_info,
      expense_report_url: expense_report_url(expense_report.id),
      admin_url: admin_expense_report_url(expense_report.id)
    }
  end

  defp validate_and_preload_expense_report(expense_report) do
    if is_nil(expense_report) do
      raise ArgumentError, "Expense report cannot be nil"
    end

    if is_nil(expense_report.id) do
      raise ArgumentError,
            "Expense report missing id: #{inspect(expense_report)}"
    end

    expense_report = ensure_expense_report_preloaded(expense_report)

    if is_nil(expense_report.user) do
      raise ArgumentError,
            "Expense report missing user association: #{expense_report.id}"
    end

    expense_report
  end

  defp ensure_expense_report_preloaded(expense_report) do
    if Ecto.assoc_loaded?(expense_report.user) &&
         Ecto.assoc_loaded?(expense_report.expense_items) &&
         Ecto.assoc_loaded?(expense_report.income_items) do
      expense_report
    else
      load_expense_report_with_preloads(expense_report.id)
    end
  end

  defp load_expense_report_with_preloads(expense_report_id) do
    case Repo.get(ExpenseReport, expense_report_id)
         |> Repo.preload([
           :user,
           :expense_items,
           :income_items,
           :event,
           :bank_account,
           :address
         ]) do
      nil ->
        raise ArgumentError, "Expense report not found: #{expense_report_id}"

      loaded_report ->
        loaded_report
    end
  end

  defp calculate_expense_total(expense_items_list) do
    expense_items_list
    |> Enum.reduce(Money.new(0, :USD), fn item, acc ->
      add_item_amount(acc, item.amount)
    end)
  end

  defp calculate_income_total(income_items_list) do
    income_items_list
    |> Enum.reduce(Money.new(0, :USD), fn item, acc ->
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

  defp calculate_net_total(expense_total, income_total) do
    case Money.sub(expense_total, income_total) do
      {:ok, result} -> result
      {:error, _} -> Money.new(0, :USD)
    end
  end

  defp format_expense_items(expense_items_list) do
    Enum.map(expense_items_list, fn item ->
      %{
        vendor: item.vendor || "N/A",
        description: item.description || "N/A",
        date: format_date(item.date),
        amount: format_money(item.amount),
        has_receipt: !is_nil(item.receipt_s3_path) && item.receipt_s3_path != ""
      }
    end)
  end

  defp format_income_items(income_items_list) do
    Enum.map(income_items_list, fn item ->
      %{
        description: item.description || "N/A",
        date: format_date(item.date),
        amount: format_money(item.amount),
        has_proof: !is_nil(item.proof_s3_path) && item.proof_s3_path != ""
      }
    end)
  end

  defp build_user_info(user) do
    %{
      name:
        "#{user.first_name || ""} #{user.last_name || ""}"
        |> String.trim(),
      email: user.email
    }
  end

  defp build_event_info(nil), do: nil

  defp build_event_info(event) do
    %{
      title: event.title,
      id: event.id,
      reference_id: event.reference_id
    }
  end

  defp build_bank_account_info(nil), do: nil

  defp build_bank_account_info(bank_account) do
    %{
      last_4: bank_account.account_number_last_4 || "N/A"
    }
  end

  defp build_address_info(nil), do: nil

  defp build_address_info(address) do
    %{
      address: address.address,
      city: address.city,
      region: address.region,
      postal_code: address.postal_code,
      country: address.country
    }
  end

  defp expense_report_url(expense_report_id) do
    YscWeb.Endpoint.url() <> "/expensereport/#{expense_report_id}/success"
  end

  defp admin_expense_report_url(expense_report_id) do
    YscWeb.Endpoint.url() <> "/admin/expense_reports/#{expense_report_id}"
  end

  defp format_reimbursement_method("bank_transfer"), do: "Bank Transfer"
  defp format_reimbursement_method("check"), do: "Check"

  defp format_reimbursement_method(method) when is_binary(method),
    do: String.capitalize(method)

  defp format_reimbursement_method(_), do: "Not specified"

  defp format_date(nil), do: "N/A"

  defp format_date(date) do
    Calendar.strftime(date, "%B %d, %Y")
  end

  defp format_datetime(nil), do: "N/A"

  defp format_datetime(datetime) do
    # Convert to PST
    pst_datetime = DateTime.shift_zone!(datetime, "America/Los_Angeles")
    Calendar.strftime(pst_datetime, "%B %d, %Y at %I:%M %p %Z")
  end

  defp format_money(%Money{} = money) do
    Money.to_string!(money,
      separator: ".",
      delimiter: ",",
      fractional_digits: 2
    )
  end

  defp format_money(_), do: "$0.00"
end
