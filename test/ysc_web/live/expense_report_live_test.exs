defmodule YscWeb.ExpenseReportLiveTest do
  @moduledoc """
  Tests for ExpenseReportLive.
  """
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ysc.ExpenseReports

  setup :register_and_log_in_user

  test "renders expense report form", %{conn: conn} do
    {:ok, _index_live, html} = live(conn, ~p"/expensereport")

    assert html =~ "Expense Report"
    assert html =~ "Amount we will reimburse"
    refute html =~ "Net Total"
  end

  test "mileage items use trip-purpose copy instead of business jargon", %{
    conn: conn
  } do
    {:ok, view, html} = live(conn, ~p"/expensereport")

    assert has_element?(view, "#expense-report-form")
    refute html =~ "Business Purpose"

    html =
      view
      |> form("#expense-report-form", %{
        "expense_report" => %{
          "expense_items" => %{"0" => %{"expense_type" => "mileage"}}
        }
      })
      |> render_change()

    assert has_element?(view, "#mileage-help-0")
    assert html =~ "Purpose of trip"
    assert html =~ "Route (from / to)"
    assert html =~ "Amount we will reimburse"
    assert html =~ "why you made the trip"
    refute html =~ "Business Purpose"
    refute html =~ "business purpose"
  end

  test "purchase items without a receipt leave the receipts checklist pending",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/expensereport")

    assert has_element?(
             view,
             "span.text-zinc-600",
             "All expense items have receipts"
           )

    refute has_element?(
             view,
             "span.line-through",
             "All expense items have receipts"
           )
  end

  test "mileage items compute reimbursement live and do not require a receipt",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/expensereport")

    view
    |> form("#expense-report-form", %{
      "expense_report" => %{
        "expense_items" => %{"0" => %{"expense_type" => "mileage"}}
      }
    })
    |> render_change()

    html =
      view
      |> form("#expense-report-form", %{
        "expense_report" => %{
          "expense_items" => %{
            "0" => %{
              "expense_type" => "mileage",
              "date" => Date.to_iso8601(Date.utc_today()),
              "description" => "Board meeting",
              "mileage_from_to" => "Home to YSC Cabin",
              "miles_driven" => "20"
            }
          }
        }
      })
      |> render_change()

    assert html =~ "20 mi ×"
    assert html =~ "$6.00"

    assert has_element?(
             view,
             "span.line-through",
             "All expense items have receipts"
           )
  end

  test "renders expense report list", %{conn: conn} do
    {:ok, _index_live, html} = live(conn, ~p"/expensereports")

    assert html =~ "Expense Report"
  end

  describe "per-row receipt uploads" do
    setup %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/expensereport")

      # Two expense items, neither with a receipt yet.
      render_click(view, "add_expense_item", %{})

      view
      |> form("#expense-report-form", %{
        "expense_report" => %{
          "expense_items" => %{
            "0" => %{
              "date" => Date.to_iso8601(Date.utc_today()),
              "vendor" => "Costco",
              "description" => "Snacks",
              "amount" => "10.00"
            },
            "1" => %{
              "date" => Date.to_iso8601(Date.utc_today()),
              "vendor" => "Target",
              "description" => "Cups",
              "amount" => "5.00"
            }
          }
        }
      })
      |> render_change()

      %{view: view}
    end

    defp upload_receipt(view) do
      receipt =
        file_input(view, "#expense-report-form", :receipt, [
          %{name: "receipt.png", content: "fake-png-bytes", type: "image/png"}
        ])

      render_upload(receipt, "receipt.png", 100)
    end

    test "an upload started from a later row attaches to that row, not the first",
         %{view: view} do
      # User taps the "add a receipt" control on the second item, then picks a file.
      view |> element("#receipt-target-1") |> render_click()
      upload_receipt(view)

      # The pending upload UI is shown only under item 1.
      assert has_element?(
               view,
               "progress[data-upload-type='receipt'][data-index='1']"
             )

      refute has_element?(
               view,
               "progress[data-upload-type='receipt'][data-index='0']"
             )

      # Attaching it lands on item 1; item 0 is still awaiting a receipt.
      view
      |> element("button[phx-click='consume-receipt'][phx-value-index='1']")
      |> render_click()

      assert has_element?(view, "#receipt-preview-1")
      refute has_element?(view, "#receipt-preview-0")

      # The same image can be uploaded again for item 0 (now the first row
      # still missing a receipt, so its dropzone is already active).
      upload_receipt(view)

      view
      |> element("button[phx-click='consume-receipt'][phx-value-index='0']")
      |> render_click()

      assert has_element?(view, "#receipt-preview-0")
      assert has_element?(view, "#receipt-preview-1")
    end

    test "adding a row mid-upload keeps the entry pinned to its original row",
         %{view: view} do
      view |> element("#receipt-target-1") |> render_click()
      upload_receipt(view)

      assert has_element?(
               view,
               "progress[data-upload-type='receipt'][data-index='1']"
             )

      # A new row appears while the upload is still pending.
      render_click(view, "add_expense_item", %{})

      # The entry stays on row 1 - it must not slide onto row 0.
      assert has_element?(
               view,
               "progress[data-upload-type='receipt'][data-index='1']"
             )

      refute has_element?(
               view,
               "progress[data-upload-type='receipt'][data-index='0']"
             )

      view
      |> element("button[phx-click='consume-receipt'][phx-value-index='1']")
      |> render_click()

      assert has_element?(view, "#receipt-preview-1")
      refute has_element?(view, "#receipt-preview-0")
    end

    test "selecting another row as target is ignored while an upload is active",
         %{view: view} do
      view |> element("#receipt-target-1") |> render_click()
      upload_receipt(view)

      # Try to re-target row 0 mid-upload.
      view |> element("#receipt-target-0") |> render_click()

      assert has_element?(
               view,
               "progress[data-upload-type='receipt'][data-index='1']"
             )

      refute has_element?(
               view,
               "progress[data-upload-type='receipt'][data-index='0']"
             )
    end

    test "removing the pinned row mid-upload cancels the entry", %{view: view} do
      view |> element("#receipt-target-1") |> render_click()
      upload_receipt(view)

      assert has_element?(view, "progress[data-upload-type='receipt']")

      view
      |> element("button[phx-click='remove_expense_item'][phx-value-index='1']")
      |> render_click()

      # No dangling entry to misattach to the remaining row.
      refute has_element?(view, "progress[data-upload-type='receipt']")
      refute has_element?(view, "#receipt-preview-0")
    end
  end

  describe "drafts" do
    # `add_expense_item` schedules an immediate (delay 0) autosave; a follow-up
    # A structural event (add row) schedules an immediate autosave by enqueueing
    # the message synchronously; the following render/1 is a sync point that lets
    # the LiveView process that message before we assert.
    defp flush_autosave(view) do
      render_click(view, "add_expense_item", %{})
      _ = render(view)
    end

    test "typing is autosaved and resumed after a page refresh", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/expensereport")

      view
      |> form("#expense-report-form", %{
        "expense_report" => %{"purpose" => "Kayak repair kit"}
      })
      |> render_change()

      flush_autosave(view)

      draft = ExpenseReports.get_active_draft(user)
      assert draft
      assert draft.purpose == "Kayak repair kit"

      # A brand-new mount (i.e. the member hit refresh) resumes the draft.
      {:ok, view2, _html2} = live(conn, ~p"/expensereport")

      assert has_element?(view2, "#expense-report-draft-banner")

      assert has_element?(
               view2,
               "#expense_report_purpose",
               "Kayak repair kit"
             )
    end

    test "an untouched form never creates a draft row", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/expensereport")

      # Structural change but no real content typed.
      render_click(view, "add_expense_item", %{})
      _ = render(view)

      assert ExpenseReports.get_active_draft(user) == nil
      refute has_element?(view, "#expense-report-draft-banner")
    end

    test "discarding a draft clears the form and deletes the row", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/expensereport")

      view
      |> form("#expense-report-form", %{
        "expense_report" => %{"purpose" => "Throwaway"}
      })
      |> render_change()

      flush_autosave(view)
      assert ExpenseReports.get_active_draft(user)

      view
      |> element(
        "#expense-report-draft-banner button[phx-click='discard-draft']"
      )
      |> render_click()

      assert ExpenseReports.get_active_draft(user) == nil
      refute has_element?(view, "#expense-report-draft-banner")
      refute has_element?(view, "#expense_report_purpose", "Throwaway")
    end

    test "a resumed draft rehydrates its saved fields and uploaded receipt", %{
      conn: conn,
      user: user
    } do
      {:ok, _draft} =
        ExpenseReports.save_draft(user, %{
          "purpose" => "Regatta catering",
          "expense_items" => %{
            "0" => %{
              "vendor" => "Safeway",
              "description" => "Sandwiches",
              "amount" => "48.20",
              "date" => "2026-02-01",
              "receipt_s3_path" => "receipts/u/regatta.pdf"
            }
          }
        })

      {:ok, view, html} = live(conn, ~p"/expensereport")

      assert html =~ "Regatta catering"
      # The item row and its previously-uploaded receipt come back.
      assert has_element?(
               view,
               "input[name='expense_report[expense_items][0][vendor]'][value='Safeway']"
             )

      assert has_element?(view, "#receipt-preview-0")
    end

    test "the reports list shows a Drafts section with a Continue link", %{
      conn: conn,
      user: user
    } do
      {:ok, draft} =
        ExpenseReports.save_draft(user, %{"purpose" => "Half-done report"})

      {:ok, view, _html} = live(conn, ~p"/expensereports")

      assert has_element?(view, "#expense-report-drafts", "Half-done report")

      assert has_element?(
               view,
               "#expense-report-draft-continue-#{draft.id}",
               "Continue"
             )
    end
  end
end
