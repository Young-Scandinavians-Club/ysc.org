defmodule Ysc.Ledgers.AdminDashboardRevenueTest do
  # Deletes globally named revenue accounts that other tests insert ledger
  # entries against. Running that in parallel deadlocks on FK row locks.
  use Ysc.DataCase, async: false

  import Ecto.Query

  alias Ysc.Ledgers
  alias Ysc.Ledgers.{LedgerAccount, LedgerEntry}
  alias Ysc.Repo

  setup do
    Ledgers.ensure_basic_accounts()
    :ok
  end

  describe "get_admin_dashboard_revenue/1" do
    test "aggregates credits and debits by period in SQL" do
      now = ~U[2026-08-20 12:00:00Z]
      membership = Ledgers.get_account_by_name("membership_revenue")
      event = Ledgers.get_account_by_name("event_revenue")
      tahoe = Ledgers.get_account_by_name("tahoe_booking_revenue")
      donation = Ledgers.get_account_by_name("donation_revenue")

      insert_entry!(membership, :credit, 100, ~U[2026-08-10 08:00:00Z])
      insert_entry!(membership, :credit, 5, ~U[2026-08-18 08:00:00Z])
      insert_entry!(membership, :debit, 20, ~U[2026-08-19 08:00:00Z])
      insert_entry!(event, :credit, 50, ~U[2026-07-15 08:00:00Z])
      insert_entry!(tahoe, :credit, 25, ~U[2025-08-10 08:00:00Z])
      insert_entry!(donation, :credit, 10, ~U[2026-01-15 08:00:00Z])

      snapshot = Ledgers.get_admin_dashboard_revenue(now)

      membership_totals =
        Map.fetch!(snapshot.totals_by_account_id, membership.id)

      event_totals = Map.fetch!(snapshot.totals_by_account_id, event.id)
      tahoe_totals = Map.fetch!(snapshot.totals_by_account_id, tahoe.id)
      donation_totals = Map.fetch!(snapshot.totals_by_account_id, donation.id)

      assert Decimal.eq?(membership_totals.current_month, Decimal.new(85))
      assert Decimal.eq?(membership_totals.prev_month, Decimal.new(0))
      assert Decimal.eq?(membership_totals.ytd, Decimal.new(85))

      assert Decimal.eq?(event_totals.current_month, Decimal.new(0))
      assert Decimal.eq?(event_totals.prev_month, Decimal.new(50))
      assert Decimal.eq?(event_totals.ytd, Decimal.new(50))

      assert Decimal.eq?(tahoe_totals.last_year_month, Decimal.new(25))
      assert Decimal.eq?(tahoe_totals.ytd, Decimal.new(0))

      assert Decimal.eq?(donation_totals.ytd, Decimal.new(10))
      assert Decimal.eq?(donation_totals.current_month, Decimal.new(0))

      # 85 membership + 50 event + 10 donation; last-year tahoe is excluded
      assert Decimal.eq?(snapshot.ytd_total, Decimal.new(145))

      assert length(snapshot.sparkline) == 7
      # 2026-08-18 credit 5 and 2026-08-19 debit 20; other sparkline days 0
      assert Enum.at(snapshot.sparkline, 4) |> Decimal.eq?(Decimal.new(5))
      assert Enum.at(snapshot.sparkline, 5) |> Decimal.eq?(Decimal.new(-20))
      assert Enum.at(snapshot.sparkline, 6) |> Decimal.eq?(Decimal.new(0))
    end

    test "returns zeroed sparkline and totals when no revenue entries exist" do
      now = ~U[2026-08-20 12:00:00Z]
      snapshot = Ledgers.get_admin_dashboard_revenue(now)

      assert snapshot.totals_by_account_id == %{}
      assert Decimal.eq?(snapshot.ytd_total, Decimal.new(0))
      assert snapshot.sparkline == List.duplicate(Decimal.new(0), 7)
    end

    test "returns empty totals when revenue accounts have not been seeded" do
      Repo.delete_all(
        from(a in LedgerAccount,
          where:
            a.name in [
              "membership_revenue",
              "event_revenue",
              "tahoe_booking_revenue",
              "clear_lake_booking_revenue",
              "donation_revenue"
            ]
        )
      )

      snapshot = Ledgers.get_admin_dashboard_revenue(~U[2026-08-20 12:00:00Z])

      assert snapshot.accounts_by_name == %{}
      assert snapshot.totals_by_account_id == %{}
      assert Decimal.eq?(snapshot.ytd_total, Decimal.new(0))
      assert snapshot.sparkline == List.duplicate(Decimal.new(0), 7)
    end
  end

  describe "ci_query_explain admin dashboard revenue queries" do
    test "ci_query_explain_admin_dashboard_revenue_totals_query/0 returns a query" do
      assert %Ecto.Query{} =
               Ledgers.ci_query_explain_admin_dashboard_revenue_totals_query()
    end

    test "ci_query_explain_admin_dashboard_revenue_sparkline_query/0 returns a query" do
      assert %Ecto.Query{} =
               Ledgers.ci_query_explain_admin_dashboard_revenue_sparkline_query()
    end
  end

  defp insert_entry!(account, debit_credit, amount, inserted_at) do
    at = DateTime.truncate(inserted_at, :second)

    %LedgerEntry{
      account_id: account.id,
      amount: Money.new(amount, :USD),
      debit_credit: debit_credit,
      description: "admin dashboard revenue test",
      inserted_at: at,
      updated_at: at
    }
    |> Repo.insert!()
  end
end
