defmodule YscWeb.Emails.MembershipEndedTest do
  @moduledoc """
  Tests for the membership-ended re-engagement email.
  """
  use Ysc.DataCase, async: true

  import Swoosh.TestAssertions
  import Ysc.AccountsFixtures

  alias Ysc.Subscriptions
  alias YscWeb.Emails.MembershipEnded

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "get_template_name/0 and get_subject/1" do
    test "returns template metadata" do
      assert MembershipEnded.get_template_name() == "membership_ended"
      assert MembershipEnded.get_subject() == "Your YSC Membership Has Ended"
      assert MembershipEnded.get_subject(%{}) == "Your YSC Membership Has Ended"
    end
  end

  describe "prepare_email_data/2" do
    test "returns assigns for a voluntary lapse", %{user: user} do
      ends_at =
        DateTime.utc_now()
        |> DateTime.add(-1, :day)
        |> DateTime.truncate(:second)

      subscription = %{
        ends_at: ends_at,
        current_period_end: ends_at,
        cancel_at_period_end: true
      }

      data = MembershipEnded.prepare_email_data(user, subscription)

      assert data.first_name == user.first_name
      assert data.end_date =~ ~r/\w+ \d+, \d{4}/
      assert data.membership_url =~ "/users/membership"
      assert data.upcoming_events_url =~ "/events"
    end

    test "uses Valued Member when first_name is blank", %{user: user} do
      ends_at = DateTime.utc_now() |> DateTime.truncate(:second)
      user = %{user | first_name: ""}

      data =
        MembershipEnded.prepare_email_data(user, %{
          ends_at: ends_at,
          current_period_end: ends_at,
          cancel_at_period_end: true
        })

      assert data.first_name == "Valued Member"
    end

    test "raises when user is nil" do
      assert_raise ArgumentError, "User cannot be nil", fn ->
        Ysc.Test.Invoke.call(MembershipEnded, :prepare_email_data, [
          nil,
          %{ends_at: DateTime.utc_now(), cancel_at_period_end: true}
        ])
      end
    end

    test "raises when subscription is nil", %{user: user} do
      assert_raise ArgumentError, "Subscription cannot be nil", fn ->
        Ysc.Test.Invoke.call(MembershipEnded, :prepare_email_data, [user, nil])
      end
    end
  end

  describe "render/1" do
    test "renders membership ended copy", %{user: user} do
      html =
        MembershipEnded.render(%{
          first_name: user.first_name,
          end_date: "August 1, 2026",
          membership_url: "https://example.com/users/membership",
          upcoming_events_url: "https://example.com/events"
        })

      doc = LazyHTML.from_document(html)
      text = LazyHTML.text(doc)

      assert text =~ user.first_name
      assert text =~ "Your Membership Has Ended"
      assert text =~ "automatic renewal was turned off"
      assert text =~ "Renew Membership"
      assert text =~ "August 1, 2026"
      assert text =~ "Tahoe and Clear Lake"
      assert text =~ "memberships@ysc.org"
      assert text =~ "Vi ses snart"
    end
  end

  describe "maybe_schedule/2" do
    test "schedules email when cancel_at_period_end is set", %{user: user} do
      ends_at =
        DateTime.utc_now()
        |> DateTime.add(-1, :day)
        |> DateTime.truncate(:second)

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_ended_email_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          name: "Ended Membership",
          current_period_end: ends_at,
          ends_at: ends_at,
          cancel_at_period_end: true
        })

      assert :ok = MembershipEnded.maybe_schedule(user, subscription)
      assert_email_sent(subject: "Your YSC Membership Has Ended")
    end

    test "skips when cancel_at_period_end is false (not a voluntary auto-renew off)",
         %{
           user: user
         } do
      past =
        DateTime.utc_now()
        |> DateTime.add(-1, :day)
        |> DateTime.truncate(:second)

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_ended_skip_#{System.unique_integer([:positive])}",
          stripe_status: "cancelled",
          name: "Payment Failure Cancel",
          current_period_end: past,
          ends_at: past,
          cancel_at_period_end: false
        })

      assert :skipped = MembershipEnded.maybe_schedule(user, subscription)
      refute_email_sent(subject: "Your YSC Membership Has Ended")
    end

    test "is idempotent for the same user and end date", %{user: user} do
      ends_at =
        DateTime.utc_now()
        |> DateTime.add(-2, :day)
        |> DateTime.truncate(:second)

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_ended_idem_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          name: "Ended Idempotent",
          current_period_end: ends_at,
          ends_at: ends_at,
          cancel_at_period_end: true
        })

      assert :ok = MembershipEnded.maybe_schedule(user, subscription)
      assert :ok = MembershipEnded.maybe_schedule(user, subscription)

      assert_email_sent(subject: "Your YSC Membership Has Ended")
      assert_no_email_sent()
    end
  end

  describe "voluntary_lapse?/1" do
    test "returns true only when cancel_at_period_end is set" do
      assert MembershipEnded.voluntary_lapse?(%{cancel_at_period_end: true})
      refute MembershipEnded.voluntary_lapse?(%{cancel_at_period_end: false})
      refute MembershipEnded.voluntary_lapse?(%{})
    end
  end

  describe "maybe_schedule_email_multi/4" do
    alias Ecto.Multi

    test "adds email job for voluntary lapse", %{user: user} do
      ends_at =
        DateTime.utc_now()
        |> DateTime.add(-1, :day)
        |> DateTime.truncate(:second)

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_multi_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          name: "Multi Email",
          current_period_end: ends_at,
          ends_at: ends_at,
          cancel_at_period_end: true
        })

      multi =
        MembershipEnded.maybe_schedule_email_multi(
          Multi.new(),
          :membership_ended_email,
          user,
          subscription
        )

      assert MapSet.member?(multi.names, :membership_ended_email)
    end

    test "returns multi unchanged when not a voluntary lapse", %{user: user} do
      past =
        DateTime.utc_now()
        |> DateTime.add(-1, :day)
        |> DateTime.truncate(:second)

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_multi_skip_#{System.unique_integer([:positive])}",
          stripe_status: "cancelled",
          name: "Not Voluntary",
          current_period_end: past,
          ends_at: past,
          cancel_at_period_end: false
        })

      multi = Multi.new()

      assert multi ==
               MembershipEnded.maybe_schedule_email_multi(
                 multi,
                 :membership_ended_email,
                 user,
                 subscription
               )
    end

    test "returns multi unchanged when user is nil" do
      multi = Multi.new()

      assert multi ==
               MembershipEnded.maybe_schedule_email_multi(
                 multi,
                 :membership_ended_email,
                 nil,
                 %{cancel_at_period_end: true}
               )
    end
  end

  describe "maybe_schedule/2 guards" do
    test "returns skipped for nil user" do
      assert :skipped =
               MembershipEnded.maybe_schedule(nil, %{cancel_at_period_end: true})
    end

    test "returns skipped for nil subscription", %{user: user} do
      assert :skipped = MembershipEnded.maybe_schedule(user, nil)
    end
  end
end
