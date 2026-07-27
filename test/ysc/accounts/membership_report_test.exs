defmodule Ysc.Accounts.MembershipReportTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Accounts.MembershipReport
  alias Ysc.Subscriptions

  describe "generate/2" do
    test "includes pending applications completed in the date range" do
      user = user_fixture()
      completed_at = ~U[2026-03-15 12:00:00Z]

      signup_application_fixture(user, %{
        completed: completed_at,
        review_outcome: nil
      })

      report = MembershipReport.generate(~D[2026-03-01], ~D[2026-03-31])

      assert report.counts.applied == 1
      assert report.counts.pending == 1
      assert length(report.pending) == 1
      assert hd(report.pending).user_id == user.id
    end

    test "deduplicates purchased users from accepted list" do
      user = user_fixture()
      reviewed_at = ~U[2026-03-10 10:00:00Z]
      start_date = ~U[2026-03-12 10:00:00Z]

      signup_application_fixture(user, %{
        completed: ~U[2026-03-05 10:00:00Z],
        review_outcome: "approved",
        reviewed_at: reviewed_at
      })

      {:ok, _subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_report_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Single Membership",
          start_date: start_date,
          current_period_end: DateTime.add(start_date, 365, :day)
        })

      report = MembershipReport.generate(~D[2026-03-01], ~D[2026-03-31])

      assert report.counts.accepted == 1
      assert report.counts.purchased == 1
      assert report.accepted == []
      assert length(report.purchased) == 1
      assert hd(report.purchased).signup_application.user_id == user.id
    end

    test "includes expired subscriptions in range" do
      user = user_fixture()
      period_end = ~U[2026-02-20 08:00:00Z]

      {:ok, _subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_expired_#{System.unique_integer()}",
          stripe_status: "canceled",
          name: "Single Membership",
          current_period_end: period_end
        })

      report = MembershipReport.generate(~D[2026-02-01], ~D[2026-02-28])

      assert report.counts.expired == 1
      assert length(report.expired) == 1
      assert hd(report.expired).user_id == user.id
    end

    test "includes rejected applications reviewed in the date range" do
      user = user_fixture()
      reviewed_at = ~U[2026-03-18 14:00:00Z]

      signup_application_fixture(user, %{
        completed: ~U[2026-03-10 09:00:00Z],
        review_outcome: "rejected",
        reviewed_at: reviewed_at
      })

      report = MembershipReport.generate(~D[2026-03-01], ~D[2026-03-31])

      assert report.counts.rejected == 1
      assert length(report.rejected) == 1
      assert hd(report.rejected).user_id == user.id
    end

    test "includes accepted applications without a purchase in range" do
      user = user_fixture()
      reviewed_at = ~U[2026-03-12 10:00:00Z]

      signup_application_fixture(user, %{
        completed: ~U[2026-03-05 10:00:00Z],
        review_outcome: "approved",
        reviewed_at: reviewed_at
      })

      report = MembershipReport.generate(~D[2026-03-01], ~D[2026-03-31])

      assert report.counts.accepted == 1
      assert length(report.accepted) == 1
      assert hd(report.accepted).user_id == user.id
    end
  end

  describe "to_csv/1" do
    test "exports pending and purchased rows with expected columns" do
      user = user_fixture()

      signup_application_fixture(user, %{
        completed: ~U[2026-04-01 09:00:00Z],
        review_outcome: nil,
        link_to_scandinavia: "Born in Stockholm",
        hear_about_the_club: "Friend",
        occupation: "Engineer",
        city: "Seattle",
        country: "US"
      })

      report = MembershipReport.generate(~D[2026-04-01], ~D[2026-04-30])
      csv = MembershipReport.to_csv(report)

      assert csv =~ "Category"
      assert csv =~ "Pending"
      assert csv =~ user.email
      assert csv =~ "Born in Stockholm"
      assert csv =~ "Friend"
      assert csv =~ "Engineer"
    end

    test "exports purchased rows with attached application details" do
      user = user_fixture()
      reviewed_at = ~U[2026-04-05 10:00:00Z]
      start_date = ~U[2026-04-06 10:00:00Z]

      signup_application_fixture(user, %{
        completed: ~U[2026-04-01 09:00:00Z],
        review_outcome: "approved",
        reviewed_at: reviewed_at,
        link_to_scandinavia: "Family in Oslo",
        hear_about_the_club: "Event",
        occupation: "Designer",
        city: "Portland",
        country: "US"
      })

      {:ok, _subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_csv_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Single Membership",
          start_date: start_date,
          current_period_end: DateTime.add(start_date, 365, :day)
        })

      report = MembershipReport.generate(~D[2026-04-01], ~D[2026-04-30])
      csv = MembershipReport.to_csv(report)

      assert csv =~ "Purchased"
      assert csv =~ user.email
    end
  end
end
