defmodule Ysc.ExpenseReportsFetchFileTest do
  @moduledoc """
  Serializes Application env mutation for the expense-report file fetcher override.
  """
  use Ysc.DataCase, async: false

  alias Ysc.ExpenseReports

  test "uses the configured expense_reports_file_fetcher" do
    prev = Application.get_env(:ysc, :expense_reports_file_fetcher)

    on_exit(fn ->
      if prev do
        Application.put_env(:ysc, :expense_reports_file_fetcher, prev)
      else
        Application.delete_env(:ysc, :expense_reports_file_fetcher)
      end
    end)

    Application.put_env(:ysc, :expense_reports_file_fetcher, fn path ->
      {:ok, "bytes:#{path}"}
    end)

    assert ExpenseReports.fetch_file("receipts/x.pdf") ==
             {:ok, "bytes:receipts/x.pdf"}
  end
end
