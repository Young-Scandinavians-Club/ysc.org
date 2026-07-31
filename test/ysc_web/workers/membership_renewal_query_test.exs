defmodule YscWeb.Workers.MembershipRenewalQueryTest do
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures

  alias Ysc.Newsletter.Subscriber
  alias Ysc.Repo
  alias Ysc.Subscriptions.Subscription
  alias YscWeb.Workers.MembershipRenewalQuery

  describe "renewal_date_from_now/1" do
    test "returns the calendar date N days from now" do
      expected =
        DateTime.utc_now()
        |> DateTime.add(14, :day)
        |> DateTime.to_date()

      assert MembershipRenewalQuery.renewal_date_from_now(14) == expected
    end
  end

  describe "utc_day_bounds/1" do
    test "returns inclusive UTC bounds for a calendar day" do
      date = ~D[2026-07-26]

      assert MembershipRenewalQuery.utc_day_bounds(date) ==
               {
                 DateTime.new!(date, ~T[00:00:00], "Etc/UTC"),
                 DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
               }
    end
  end

  describe "list_subscriptions_renewing_on/1" do
    test "returns active subscriptions renewing on the given day" do
      user = user_fixture()
      renewal_date = ~D[2026-07-26]

      renewal_at =
        DateTime.new!(renewal_date, ~T[12:00:00], "Etc/UTC")
        |> DateTime.truncate(:second)

      matching = insert_subscription(user, renewal_at)

      other_user = user_fixture()

      other_renewal_at =
        DateTime.new!(Date.add(renewal_date, 1), ~T[12:00:00], "Etc/UTC")
        |> DateTime.truncate(:second)

      insert_subscription(other_user, other_renewal_at)

      results =
        MembershipRenewalQuery.list_subscriptions_renewing_on(renewal_date)

      assert Enum.map(results, & &1.id) == [matching.id]
      assert hd(results).user.id == user.id
    end

    test "includes WP-migrated trialing subscriptions renewing on the given day" do
      user = user_fixture()
      mark_wp_migrated!(user)
      renewal_date = ~D[2026-08-01]

      renewal_at =
        DateTime.new!(renewal_date, ~T[09:30:00], "Etc/UTC")
        |> DateTime.truncate(:second)

      matching =
        insert_subscription(user, renewal_at, stripe_status: "trialing")

      results =
        MembershipRenewalQuery.list_subscriptions_renewing_on(renewal_date)

      assert Enum.map(results, & &1.id) == [matching.id]
    end

    test "excludes organic trialing subscriptions without WP migration flag" do
      user = user_fixture()
      renewal_date = ~D[2026-08-01]

      renewal_at =
        DateTime.new!(renewal_date, ~T[09:30:00], "Etc/UTC")
        |> DateTime.truncate(:second)

      insert_subscription(user, renewal_at, stripe_status: "trialing")

      assert MembershipRenewalQuery.list_subscriptions_renewing_on(renewal_date) ==
               []
    end

    test "excludes canceled and scheduled-to-end subscriptions" do
      user = user_fixture()
      renewal_date = ~D[2026-08-01]

      renewal_at =
        DateTime.new!(renewal_date, ~T[09:30:00], "Etc/UTC")
        |> DateTime.truncate(:second)

      insert_subscription(user, renewal_at, stripe_status: "canceled")

      ending_user = user_fixture()

      insert_subscription(ending_user, renewal_at,
        ends_at:
          DateTime.new!(Date.add(renewal_date, -1), ~T[12:00:00], "Etc/UTC")
          |> DateTime.truncate(:second)
      )

      assert MembershipRenewalQuery.list_subscriptions_renewing_on(renewal_date) ==
               []
    end
  end

  describe "list_subscriptions_renewing_in_days/1" do
    test "returns subscriptions renewing on the target day" do
      user = user_fixture()

      renewal_date =
        DateTime.utc_now()
        |> DateTime.add(7, :day)
        |> DateTime.to_date()

      renewal_at =
        DateTime.new!(renewal_date, ~T[15:00:00], "Etc/UTC")
        |> DateTime.truncate(:second)

      matching = insert_subscription(user, renewal_at)

      assert Enum.map(
               MembershipRenewalQuery.list_subscriptions_renewing_in_days(7),
               & &1.id
             ) == [matching.id]
    end
  end

  describe "list_subscriptions_renewing_within_days/1" do
    test "returns subscriptions renewing today through N days out" do
      user_today = user_fixture()
      user_soon = user_fixture()
      user_far = user_fixture()

      today = Date.utc_today()

      today_sub =
        insert_subscription(
          user_today,
          DateTime.new!(today, ~T[12:00:00], "Etc/UTC")
          |> DateTime.truncate(:second)
        )

      soon_sub =
        insert_subscription(
          user_soon,
          DateTime.new!(Date.add(today, 3), ~T[12:00:00], "Etc/UTC")
          |> DateTime.truncate(:second)
        )

      insert_subscription(
        user_far,
        DateTime.new!(Date.add(today, 10), ~T[12:00:00], "Etc/UTC")
        |> DateTime.truncate(:second)
      )

      ids =
        MembershipRenewalQuery.list_subscriptions_renewing_within_days(7)
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert ids == Enum.sort([today_sub.id, soon_sub.id])
    end
  end

  defp mark_wp_migrated!(user) do
    case Repo.get_by(Subscriber, email: user.email) do
      nil ->
        %Subscriber{}
        |> Subscriber.create_changeset(%{
          email: user.email,
          user_id: user.id,
          source: "wp_migration",
          subscribed: true,
          subscribed_at: DateTime.utc_now() |> DateTime.truncate(:second),
          subscription_token: Subscriber.generate_subscription_token()
        })
        |> Repo.insert!()

      subscriber ->
        subscriber
        |> Subscriber.update_changeset(%{
          user_id: user.id,
          source: "wp_migration"
        })
        |> Repo.update!()
    end
  end

  defp insert_subscription(user, renewal_date, opts \\ []) do
    stripe_status = Keyword.get(opts, :stripe_status, "active")
    ends_at = Keyword.get(opts, :ends_at, nil)

    renewal_date_truncated = DateTime.truncate(renewal_date, :second)

    ends_at_truncated =
      if ends_at, do: DateTime.truncate(ends_at, :second), else: nil

    start_date =
      DateTime.utc_now()
      |> DateTime.add(-30, :day)
      |> DateTime.truncate(:second)

    %Subscription{
      user_id: user.id,
      stripe_id: "sub_query_#{System.unique_integer([:positive])}",
      stripe_status: stripe_status,
      name: "membership",
      current_period_end: renewal_date_truncated,
      current_period_start: start_date,
      ends_at: ends_at_truncated
    }
    |> Repo.insert!()
  end
end
