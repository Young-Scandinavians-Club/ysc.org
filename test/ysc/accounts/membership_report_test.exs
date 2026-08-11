defmodule Ysc.Accounts.MembershipReportTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Accounts
  alias Ysc.Accounts.MembershipReport
  alias Ysc.Subscriptions

  describe "generate/2" do
    test "includes pending applications completed in the date range" do
      user = user_fixture(%{state: :pending_approval})
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

      signup_application_fixture(user)

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

    test "a user activated via a direct account-status edit shows as accepted, not pending" do
      admin = user_fixture(%{role: :admin, phone_number: unique_user_phone()})
      user = user_fixture(%{state: :pending_approval})

      signup_application_fixture(user, %{
        completed: DateTime.utc_now(),
        review_outcome: nil
      })

      assert {:ok, _updated} =
               Accounts.update_user_with_address(
                 user,
                 %{
                   "first_name" => user.first_name,
                   "last_name" => user.last_name,
                   "state" => "active",
                   "billing_address" => %{
                     "address" => "",
                     "city" => "",
                     "region" => "",
                     "postal_code" => "",
                     "country" => ""
                   }
                 },
                 admin
               )

      today = Date.utc_today()

      report =
        MembershipReport.generate(Date.add(today, -1), Date.add(today, 1))

      assert report.counts.accepted == 1
      assert report.counts.pending == 0
      assert length(report.accepted) == 1
      assert hd(report.accepted).user_id == user.id
    end

    test "a rejected user reactivated via the rejection-override flow shows as accepted, not rejected" do
      admin = user_fixture(%{role: :admin, phone_number: unique_user_phone()})
      user = user_fixture(%{state: :rejected})

      signup_application_fixture(user, %{
        completed: DateTime.add(DateTime.utc_now(), -2, :day),
        review_outcome: "rejected",
        reviewed_at: DateTime.add(DateTime.utc_now(), -2, :day)
      })

      assert {:ok, _updated} =
               Accounts.update_user_with_address_and_rejection_override_note(
                 user,
                 %{
                   "first_name" => user.first_name,
                   "last_name" => user.last_name,
                   "state" => "active",
                   "billing_address" => %{
                     "address" => "",
                     "city" => "",
                     "region" => "",
                     "postal_code" => "",
                     "country" => ""
                   }
                 },
                 "Reactivated on appeal",
                 admin
               )

      today = Date.utc_today()

      report =
        MembershipReport.generate(Date.add(today, -5), Date.add(today, 1))

      assert report.counts.accepted == 1
      assert report.counts.rejected == 0
      assert hd(report.accepted).user_id == user.id
    end

    test "classifies a repurchase after a real lapse as returning, not purchased" do
      user = user_fixture()
      signup_application_fixture(user)

      {:ok, _old_sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_returning_old_#{System.unique_integer()}",
          stripe_status: "canceled",
          name: "Single Membership",
          start_date: ~U[2025-01-01 10:00:00Z],
          current_period_end: ~U[2025-12-01 10:00:00Z]
        })

      {:ok, _new_sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_returning_new_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Single Membership",
          start_date: ~U[2026-03-10 10:00:00Z],
          current_period_end: ~U[2027-03-10 10:00:00Z]
        })

      report = MembershipReport.generate(~D[2026-03-01], ~D[2026-03-31])

      assert report.counts.returning == 1
      assert report.counts.purchased == 0
      assert length(report.returning) == 1
      assert hd(report.returning).user_id == user.id
    end

    test "excludes a repurchase when the member already had coverage at the report's start date" do
      user = user_fixture()
      signup_application_fixture(user)

      {:ok, _covering_sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_excluded_old_#{System.unique_integer()}",
          stripe_status: "canceled",
          name: "Single Membership",
          start_date: ~U[2025-06-01 10:00:00Z],
          current_period_end: ~U[2026-03-10 10:00:00Z]
        })

      {:ok, _new_sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_excluded_new_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Single Membership",
          start_date: ~U[2026-03-15 10:00:00Z],
          current_period_end: ~U[2027-03-15 10:00:00Z]
        })

      report = MembershipReport.generate(~D[2026-03-01], ~D[2026-03-31])

      assert report.counts.purchased == 0
      assert report.counts.returning == 0
      assert report.purchased == []
      assert report.returning == []
    end

    test "a previously-accepted user rejected via a direct account-status edit shows as rejected" do
      admin = user_fixture(%{role: :admin, phone_number: unique_user_phone()})
      user = user_fixture(%{state: :active})

      signup_application_fixture(user, %{
        completed: DateTime.add(DateTime.utc_now(), -3, :day),
        review_outcome: "approved",
        reviewed_at: DateTime.add(DateTime.utc_now(), -3, :day)
      })

      assert {:ok, _updated} =
               Accounts.update_user_with_address(
                 user,
                 %{
                   "first_name" => user.first_name,
                   "last_name" => user.last_name,
                   "state" => "rejected",
                   "billing_address" => %{
                     "address" => "",
                     "city" => "",
                     "region" => "",
                     "postal_code" => "",
                     "country" => ""
                   }
                 },
                 admin
               )

      today = Date.utc_today()

      report =
        MembershipReport.generate(Date.add(today, -5), Date.add(today, 1))

      assert report.counts.rejected == 1
      assert report.counts.accepted == 0
      assert hd(report.rejected).user_id == user.id
    end

    test "a previously-accepted user reverted to pending approval shows as pending again" do
      admin = user_fixture(%{role: :admin, phone_number: unique_user_phone()})
      user = user_fixture(%{state: :active})

      signup_application_fixture(user, %{
        completed: DateTime.add(DateTime.utc_now(), -3, :day),
        review_outcome: "approved",
        reviewed_at: DateTime.add(DateTime.utc_now(), -3, :day)
      })

      assert {:ok, _updated} =
               Accounts.update_user_with_address(
                 user,
                 %{
                   "first_name" => user.first_name,
                   "last_name" => user.last_name,
                   "state" => "pending_approval",
                   "billing_address" => %{
                     "address" => "",
                     "city" => "",
                     "region" => "",
                     "postal_code" => "",
                     "country" => ""
                   }
                 },
                 admin
               )

      today = Date.utc_today()

      report =
        MembershipReport.generate(Date.add(today, -5), Date.add(today, 1))

      assert report.counts.pending == 1
      assert report.counts.accepted == 0
      assert hd(report.pending).user_id == user.id
    end

    test "a user moved outside the review pipeline (e.g. suspended) is excluded from the report" do
      admin = user_fixture(%{role: :admin, phone_number: unique_user_phone()})
      user = user_fixture(%{state: :active})

      signup_application_fixture(user, %{
        completed: DateTime.add(DateTime.utc_now(), -3, :day),
        review_outcome: "approved",
        reviewed_at: DateTime.add(DateTime.utc_now(), -3, :day)
      })

      assert {:ok, _updated} =
               Accounts.update_user_with_address(
                 user,
                 %{
                   "first_name" => user.first_name,
                   "last_name" => user.last_name,
                   "state" => "suspended",
                   "billing_address" => %{
                     "address" => "",
                     "city" => "",
                     "region" => "",
                     "postal_code" => "",
                     "country" => ""
                   }
                 },
                 admin
               )

      today = Date.utc_today()

      report =
        MembershipReport.generate(Date.add(today, -5), Date.add(today, 1))

      assert report.counts.pending == 0
      assert report.counts.accepted == 0
      assert report.counts.rejected == 0
      assert report.pending == []
      assert report.accepted == []
      assert report.rejected == []
    end

    test "an application approved outside the report window is not reported as pending or accepted" do
      user = user_fixture()

      signup_application_fixture(user, %{
        completed: ~U[2026-03-05 10:00:00Z],
        review_outcome: "approved",
        reviewed_at: ~U[2026-02-01 10:00:00Z]
      })

      report = MembershipReport.generate(~D[2026-03-01], ~D[2026-03-31])

      assert report.counts.pending == 0
      assert report.counts.accepted == 0
      assert report.pending == []
      assert report.accepted == []
    end

    test "a subscription with no start_date is ignored when classifying a later purchase" do
      user = user_fixture()
      signup_application_fixture(user)

      {:ok, _undated_sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_no_start_date_#{System.unique_integer()}",
          stripe_status: "canceled",
          name: "Single Membership",
          current_period_end: ~U[2025-06-01 10:00:00Z]
        })

      {:ok, _new_sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_no_start_date_new_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Single Membership",
          start_date: ~U[2026-03-10 10:00:00Z],
          current_period_end: ~U[2027-03-10 10:00:00Z]
        })

      report = MembershipReport.generate(~D[2026-03-01], ~D[2026-03-31])

      assert report.counts.purchased == 1
      assert report.counts.returning == 0
      assert hd(report.purchased).user_id == user.id
    end

    test "includes expired subscriptions recorded with the legacy 'cancelled' spelling" do
      user = user_fixture()
      period_end = ~U[2026-02-20 08:00:00Z]

      signup_application_fixture(user)

      {:ok, _subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_cancelled_spelling_#{System.unique_integer()}",
          stripe_status: "cancelled",
          name: "Single Membership",
          current_period_end: period_end
        })

      report = MembershipReport.generate(~D[2026-02-01], ~D[2026-02-28])

      assert report.counts.expired == 1
      assert length(report.expired) == 1
      assert hd(report.expired).user_id == user.id
    end

    test "excludes family sub-accounts even when they have their own application or subscription" do
      primary = user_fixture()
      sub_account = user_fixture()

      sub_account
      |> Ecto.Changeset.change(primary_user_id: primary.id)
      |> Repo.update!()

      signup_application_fixture(sub_account, %{
        completed: ~U[2026-03-05 10:00:00Z],
        review_outcome: "approved",
        reviewed_at: ~U[2026-03-12 10:00:00Z]
      })

      {:ok, _subscription} =
        Subscriptions.create_subscription(%{
          user_id: sub_account.id,
          stripe_id: "sub_family_member_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Single Membership",
          start_date: ~U[2026-03-15 10:00:00Z],
          current_period_end: ~U[2027-03-15 10:00:00Z]
        })

      report = MembershipReport.generate(~D[2026-03-01], ~D[2026-03-31])

      assert report.counts.applied == 0
      assert report.counts.accepted == 0
      assert report.counts.purchased == 0
      assert report.accepted == []
      assert report.purchased == []
    end

    test "an application accepted before the audit trail existed shows as accepted, not pending" do
      user = user_fixture(%{state: :active})
      completed_at = ~U[2026-03-05 10:00:00Z]

      signup_application_fixture(user, %{
        completed: completed_at,
        review_outcome: nil
      })

      report = MembershipReport.generate(~D[2026-03-01], ~D[2026-03-31])

      assert report.counts.accepted == 1
      assert report.counts.pending == 0
      assert length(report.accepted) == 1
      assert hd(report.accepted).user_id == user.id
    end

    test "excludes a subscription for a user with no signup application on file" do
      user = user_fixture()

      {:ok, _subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_no_application_#{System.unique_integer()}",
          stripe_status: "trialing",
          name: "Family Membership",
          start_date: ~U[2026-03-15 10:00:00Z],
          current_period_end: ~U[2028-03-15 10:00:00Z]
        })

      report = MembershipReport.generate(~D[2026-03-01], ~D[2026-03-31])

      assert report.counts.purchased == 0
      assert report.counts.returning == 0
      assert report.purchased == []
      assert report.returning == []
    end
  end

  describe "to_csv/1" do
    test "exports pending and purchased rows with expected columns" do
      user = user_fixture(%{state: :pending_approval})

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
      assert csv =~ "Family in Oslo"
      assert csv =~ "Event"
      assert csv =~ "Designer"
      assert csv =~ "Portland"
    end

    test "exports expired rows without attached application details" do
      user = user_fixture()
      period_end = ~U[2026-04-10 08:00:00Z]

      signup_application_fixture(user)

      {:ok, _subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_csv_expired_#{System.unique_integer()}",
          stripe_status: "canceled",
          name: "Single Membership",
          current_period_end: period_end
        })

      report = MembershipReport.generate(~D[2026-04-01], ~D[2026-04-30])
      csv = MembershipReport.to_csv(report)

      assert csv =~ "Expired"
      assert csv =~ user.email
      refute csv =~ "Family in Oslo"
    end

    test "formats eligibility values in csv rows" do
      user = user_fixture()

      signup_application_fixture(user, %{
        completed: ~U[2026-04-01 09:00:00Z],
        review_outcome: nil,
        membership_eligibility: [:born_in_scandinavia, :citizen_of_scandinavia]
      })

      report = MembershipReport.generate(~D[2026-04-01], ~D[2026-04-30])
      csv = MembershipReport.to_csv(report)

      assert csv =~ "I was born in Scandinavia"
      assert csv =~ "I am a citizen of a Scandinavian country"
    end
  end
end
