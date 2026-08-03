defmodule YscWeb.Emails.WelcomeEmailTest do
  @moduledoc """
  Tests for YscWeb.Emails.WelcomeEmail email template.
  """
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.BookingsFixtures

  alias Ysc.Bookings.Season
  alias Ysc.Repo
  alias YscWeb.Emails.WelcomeEmail

  setup do
    clear_seasons!()
    :ok
  end

  describe "get_template_name/0" do
    test "returns welcome_email" do
      assert WelcomeEmail.get_template_name() == "welcome_email"
    end
  end

  describe "get_subject/0" do
    test "returns a subject" do
      assert WelcomeEmail.get_subject() == "Getting started at YSC"
    end
  end

  describe "prepare_email_data/1" do
    test "raises when user is nil" do
      assert_raise ArgumentError, "User cannot be nil", fn ->
        Ysc.Test.Invoke.call(WelcomeEmail, :prepare_email_data, [nil])
      end
    end

    test "uses the member's first name" do
      user = oauth_user_fixture(%{first_name: "Jane", last_name: "Doe"})
      data = WelcomeEmail.prepare_email_data(user)
      assert data.first_name == "Jane"
    end

    test "uses Valued Member when user has no first_name" do
      base_user = oauth_user_fixture()
      user = %{base_user | first_name: nil}
      data = WelcomeEmail.prepare_email_data(user)
      assert data.first_name == "Valued Member"
    end

    test "returns no more than 3 upcoming events, ordered soonest-first" do
      user = oauth_user_fixture()
      today = DateTime.utc_now()

      event_a =
        event_fixture(%{
          title: "Soonest",
          start_date: DateTime.add(today, 1, :day)
        })

      event_b =
        event_fixture(%{
          title: "Second",
          start_date: DateTime.add(today, 2, :day)
        })

      event_c =
        event_fixture(%{
          title: "Third",
          start_date: DateTime.add(today, 3, :day)
        })

      _event_d =
        event_fixture(%{
          title: "Fourth",
          start_date: DateTime.add(today, 4, :day)
        })

      data = WelcomeEmail.prepare_email_data(user)

      assert length(data.events) == 3

      assert Enum.map(data.events, & &1.title) == [
               event_a.title,
               event_b.title,
               event_c.title
             ]

      [first_event | _] = data.events
      assert first_event.url =~ "/events/#{event_a.id}"
    end

    test "returns an empty events list when there are no upcoming events" do
      user = oauth_user_fixture()
      data = WelcomeEmail.prepare_email_data(user)
      assert data.events == []
    end

    test "treats missing season data as buyout-allowed" do
      user = oauth_user_fixture()
      data = WelcomeEmail.prepare_email_data(user)

      assert data.tahoe_buyout_allowed == true
      assert data.tahoe_season_name == "the current season"
    end

    test "reflects an active Winter season as buyout-not-allowed" do
      user = oauth_user_fixture()
      today = Date.utc_today()

      %Season{}
      |> Season.changeset(%{
        name: "Winter",
        property: :tahoe,
        start_date: Date.add(today, -10),
        end_date: Date.add(today, 10),
        is_default: false
      })
      |> Repo.insert!()

      data = WelcomeEmail.prepare_email_data(user)

      assert data.tahoe_buyout_allowed == false
      assert data.tahoe_season_name == "Winter"
    end

    test "reflects an active Summer season as buyout-allowed" do
      user = oauth_user_fixture()
      today = Date.utc_today()

      %Season{}
      |> Season.changeset(%{
        name: "Summer",
        property: :tahoe,
        start_date: Date.add(today, -10),
        end_date: Date.add(today, 10),
        is_default: true
      })
      |> Repo.insert!()

      data = WelcomeEmail.prepare_email_data(user)

      assert data.tahoe_buyout_allowed == true
      assert data.tahoe_season_name == "Summer"
    end
  end
end
