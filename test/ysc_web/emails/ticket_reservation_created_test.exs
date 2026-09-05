defmodule YscWeb.Emails.TicketReservationCreatedTest do
  @moduledoc """
  Regression tests for ticket reservation notification email data and subject lines.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Events.TicketReservation
  alias Ysc.Repo
  alias YscWeb.Emails.TicketReservationCreated

  describe "get_subject/1" do
    test "includes event title when present and non-empty" do
      subject =
        TicketReservationCreated.get_subject(%{event_title: "Winter Gala"})

      assert subject =~ "Winter Gala"
      assert subject =~ "[YSC]"
    end

    test "uses generic subject when title is blank or absent" do
      generic = "[YSC] Tickets reserved for you"

      assert TicketReservationCreated.get_subject(%{event_title: ""}) == generic
      assert TicketReservationCreated.get_subject(%{}) == generic
    end
  end

  describe "prepare_email_data/1" do
    test "builds assigns from a persisted reservation" do
      staff = user_fixture()
      member = user_fixture()

      event =
        event_fixture(%{
          organizer_id: staff.id,
          description: "Doors at six."
        })

      tier = ticket_tier_fixture(%{event_id: event.id, name: "Member GA"})

      expires_at =
        DateTime.utc_now()
        |> DateTime.truncate(:second)
        |> DateTime.add(1, :day)

      assert {:ok, reservation} =
               %TicketReservation{}
               |> TicketReservation.changeset(%{
                 ticket_tier_id: tier.id,
                 user_id: member.id,
                 created_by_id: staff.id,
                 quantity: 3,
                 discount_percentage: Decimal.new("12.5"),
                 expires_at: expires_at,
                 notes: "Gate B",
                 status: "active"
               })
               |> Repo.insert()

      data = TicketReservationCreated.prepare_email_data(reservation)

      assert data.first_name == member.first_name
      assert data.event_title == event.title
      assert data.event.description == "Doors at six."
      assert data.quantity == 3
      assert data.ticket_tier_name == "Member GA"
      assert data.has_discount
      assert data.discount_display =~ "12.5"
      assert data.has_notes
      assert data.notes_text == "Gate B"
      assert data.reserved_by_display =~ staff.first_name
      assert data.event_url =~ "/events/#{event.id}"
      assert data.notification_settings_url =~ "/users/notifications"
      assert is_binary(data.event_date_time)
      refute data.hold_expires_display =~ "checkout"
    end

    test "treats zero discount as no discount" do
      staff = user_fixture()
      member = user_fixture()
      event = event_fixture(%{organizer_id: staff.id})
      tier = ticket_tier_fixture(%{event_id: event.id})

      assert {:ok, reservation} =
               %TicketReservation{}
               |> TicketReservation.changeset(%{
                 ticket_tier_id: tier.id,
                 user_id: member.id,
                 created_by_id: staff.id,
                 quantity: 1,
                 discount_percentage: Decimal.new(0),
                 status: "active"
               })
               |> Repo.insert()

      data = TicketReservationCreated.prepare_email_data(reservation)

      refute data.has_discount
      assert data.discount_display == "None"
    end

    test "omits whitespace-only notes and formats holds without an expiry" do
      staff = user_fixture()
      member = user_fixture()

      event =
        event_fixture(%{
          organizer_id: staff.id,
          start_date: nil,
          end_date: nil,
          start_time: nil,
          end_time: nil
        })

      assert is_nil(event.start_date)

      tier = ticket_tier_fixture(%{event_id: event.id})

      assert {:ok, reservation} =
               %TicketReservation{}
               |> TicketReservation.changeset(%{
                 ticket_tier_id: tier.id,
                 user_id: member.id,
                 created_by_id: staff.id,
                 quantity: 1,
                 expires_at: nil,
                 notes: "   \n  ",
                 status: "active"
               })
               |> Repo.insert()

      data = TicketReservationCreated.prepare_email_data(reservation)

      refute data.has_notes
      assert data.notes_text == nil
      assert data.event_date_time == nil
      assert data.hold_expires_display =~ "No deadline"
    end
  end
end
