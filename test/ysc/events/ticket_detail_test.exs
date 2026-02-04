defmodule Ysc.Events.TicketDetailTest do
  @moduledoc """
  Tests for TicketDetail schema.

  These tests verify:
  - Changeset validations
  - Required fields
  - Email format validation
  - Foreign key constraints
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Events.{Ticket, TicketDetail}
  alias Ysc.Repo

  setup do
    user = user_fixture()

    # Give user lifetime membership
    user =
      user
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Repo.update!()

    organizer = user_fixture()

    {:ok, event} =
      Ysc.Events.create_event(%{
        title: "Test Event",
        description: "A test event",
        state: :published,
        organizer_id: organizer.id,
        start_date:
          DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), 30, :day),
        max_attendees: 100,
        published_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    {:ok, tier} =
      Ysc.Events.create_ticket_tier(%{
        name: "General Admission",
        type: :paid,
        price: Money.new(50, :USD),
        quantity: 100,
        event_id: event.id
      })

    {:ok, ticket_order} =
      Ysc.Tickets.create_ticket_order(user.id, event.id, %{tier.id => 1})

    # Get the ticket from the order
    ticket =
      Repo.one(
        from t in Ticket, where: t.ticket_order_id == ^ticket_order.id, limit: 1
      )

    %{ticket: ticket}
  end

  describe "changeset/2" do
    test "creates valid changeset with all required fields", %{ticket: ticket} do
      attrs = %{
        ticket_id: ticket.id,
        first_name: "John",
        last_name: "Doe",
        email: "john.doe@example.com"
      }

      changeset = TicketDetail.changeset(%TicketDetail{}, attrs)

      assert changeset.valid?
      assert changeset.changes.first_name == "John"
      assert changeset.changes.last_name == "Doe"
      assert changeset.changes.email == "john.doe@example.com"
    end

    test "requires ticket_id" do
      attrs = %{
        first_name: "John",
        last_name: "Doe",
        email: "john.doe@example.com"
      }

      changeset = TicketDetail.changeset(%TicketDetail{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:ticket_id] != nil
    end

    test "requires first_name" do
      attrs = %{
        ticket_id: Ecto.ULID.generate(),
        last_name: "Doe",
        email: "john.doe@example.com"
      }

      changeset = TicketDetail.changeset(%TicketDetail{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:first_name] != nil
    end

    test "requires last_name" do
      attrs = %{
        ticket_id: Ecto.ULID.generate(),
        first_name: "John",
        email: "john.doe@example.com"
      }

      changeset = TicketDetail.changeset(%TicketDetail{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:last_name] != nil
    end

    test "requires email" do
      attrs = %{
        ticket_id: Ecto.ULID.generate(),
        first_name: "John",
        last_name: "Doe"
      }

      changeset = TicketDetail.changeset(%TicketDetail{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:email] != nil
    end

    test "validates email format" do
      attrs = %{
        ticket_id: Ecto.ULID.generate(),
        first_name: "John",
        last_name: "Doe",
        email: "invalid-email"
      }

      changeset = TicketDetail.changeset(%TicketDetail{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:email] != nil
    end

    test "accepts valid email formats", %{ticket: ticket} do
      valid_emails = [
        "user@example.com",
        "user.name@example.com",
        "user+tag@example.co.uk",
        "user_name@example-domain.com"
      ]

      for email <- valid_emails do
        attrs = %{
          ticket_id: ticket.id,
          first_name: "John",
          last_name: "Doe",
          email: email
        }

        changeset = TicketDetail.changeset(%TicketDetail{}, attrs)
        assert changeset.valid?, "Email #{email} should be valid"
      end
    end

    test "rejects invalid email formats" do
      invalid_emails = [
        "invalid-email",
        "@example.com",
        "user@",
        "user @example.com",
        ""
      ]

      for email <- invalid_emails do
        attrs = %{
          ticket_id: Ecto.ULID.generate(),
          first_name: "John",
          last_name: "Doe",
          email: email
        }

        changeset = TicketDetail.changeset(%TicketDetail{}, attrs)
        refute changeset.valid?, "Email #{email} should be invalid"
        assert changeset.errors[:email] != nil
      end
    end

    test "can insert valid ticket detail", %{ticket: ticket} do
      attrs = %{
        ticket_id: ticket.id,
        first_name: "Jane",
        last_name: "Smith",
        email: "jane.smith@example.com"
      }

      changeset = TicketDetail.changeset(%TicketDetail{}, attrs)

      assert {:ok, ticket_detail} = Repo.insert(changeset)
      assert ticket_detail.ticket_id == ticket.id
      assert ticket_detail.first_name == "Jane"
      assert ticket_detail.last_name == "Smith"
      assert ticket_detail.email == "jane.smith@example.com"
    end

    test "changeset with default empty attrs" do
      # Test default parameter
      changeset = TicketDetail.changeset(%TicketDetail{})

      refute changeset.valid?
      assert changeset.errors[:ticket_id] != nil
      assert changeset.errors[:first_name] != nil
      assert changeset.errors[:last_name] != nil
      assert changeset.errors[:email] != nil
    end
  end
end
