defmodule Ysc.Events.TicketReservationTest do
  use Ysc.DataCase, async: true

  alias Ysc.Events.TicketReservation

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      attrs = %{
        ticket_tier_id: Ecto.ULID.generate(),
        user_id: Ecto.ULID.generate(),
        created_by_id: Ecto.ULID.generate(),
        quantity: 2
      }

      changeset = TicketReservation.changeset(%TicketReservation{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset with optional fields" do
      attrs = %{
        ticket_tier_id: Ecto.ULID.generate(),
        user_id: Ecto.ULID.generate(),
        created_by_id: Ecto.ULID.generate(),
        quantity: 3,
        discount_percentage: Decimal.new("15.5"),
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
        notes: "VIP reservation",
        status: "active"
      }

      changeset = TicketReservation.changeset(%TicketReservation{}, attrs)
      assert changeset.valid?
    end

    test "invalid changeset when missing ticket_tier_id" do
      attrs = %{
        user_id: Ecto.ULID.generate(),
        created_by_id: Ecto.ULID.generate(),
        quantity: 2
      }

      changeset = TicketReservation.changeset(%TicketReservation{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).ticket_tier_id
    end

    test "invalid changeset when missing user_id" do
      attrs = %{
        ticket_tier_id: Ecto.ULID.generate(),
        created_by_id: Ecto.ULID.generate(),
        quantity: 2
      }

      changeset = TicketReservation.changeset(%TicketReservation{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).user_id
    end

    test "invalid changeset when missing created_by_id" do
      attrs = %{
        ticket_tier_id: Ecto.ULID.generate(),
        user_id: Ecto.ULID.generate(),
        quantity: 2
      }

      changeset = TicketReservation.changeset(%TicketReservation{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).created_by_id
    end

    test "invalid changeset when missing quantity" do
      attrs = %{
        ticket_tier_id: Ecto.ULID.generate(),
        user_id: Ecto.ULID.generate(),
        created_by_id: Ecto.ULID.generate()
      }

      changeset = TicketReservation.changeset(%TicketReservation{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).quantity
    end

    test "invalid changeset when quantity is zero" do
      attrs = %{
        ticket_tier_id: Ecto.ULID.generate(),
        user_id: Ecto.ULID.generate(),
        created_by_id: Ecto.ULID.generate(),
        quantity: 0
      }

      changeset = TicketReservation.changeset(%TicketReservation{}, attrs)
      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).quantity
    end

    test "invalid changeset when quantity is negative" do
      attrs = %{
        ticket_tier_id: Ecto.ULID.generate(),
        user_id: Ecto.ULID.generate(),
        created_by_id: Ecto.ULID.generate(),
        quantity: -1
      }

      changeset = TicketReservation.changeset(%TicketReservation{}, attrs)
      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).quantity
    end

    test "invalid changeset when discount_percentage is negative" do
      attrs = %{
        ticket_tier_id: Ecto.ULID.generate(),
        user_id: Ecto.ULID.generate(),
        created_by_id: Ecto.ULID.generate(),
        quantity: 1,
        discount_percentage: Decimal.new("-10")
      }

      changeset = TicketReservation.changeset(%TicketReservation{}, attrs)
      refute changeset.valid?

      assert "must be greater than or equal to 0" in errors_on(changeset).discount_percentage
    end

    test "invalid changeset when discount_percentage exceeds 100" do
      attrs = %{
        ticket_tier_id: Ecto.ULID.generate(),
        user_id: Ecto.ULID.generate(),
        created_by_id: Ecto.ULID.generate(),
        quantity: 1,
        discount_percentage: Decimal.new("101")
      }

      changeset = TicketReservation.changeset(%TicketReservation{}, attrs)
      refute changeset.valid?

      assert "must be less than or equal to 100" in errors_on(changeset).discount_percentage
    end

    test "valid changeset with discount_percentage at 0" do
      attrs = %{
        ticket_tier_id: Ecto.ULID.generate(),
        user_id: Ecto.ULID.generate(),
        created_by_id: Ecto.ULID.generate(),
        quantity: 1,
        discount_percentage: Decimal.new("0")
      }

      changeset = TicketReservation.changeset(%TicketReservation{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset with discount_percentage at 100" do
      attrs = %{
        ticket_tier_id: Ecto.ULID.generate(),
        user_id: Ecto.ULID.generate(),
        created_by_id: Ecto.ULID.generate(),
        quantity: 1,
        discount_percentage: Decimal.new("100")
      }

      changeset = TicketReservation.changeset(%TicketReservation{}, attrs)
      assert changeset.valid?
    end

    test "invalid changeset when status is invalid" do
      attrs = %{
        ticket_tier_id: Ecto.ULID.generate(),
        user_id: Ecto.ULID.generate(),
        created_by_id: Ecto.ULID.generate(),
        quantity: 1,
        status: "invalid_status"
      }

      changeset = TicketReservation.changeset(%TicketReservation{}, attrs)
      refute changeset.valid?

      assert "must be one of: active, fulfilled, cancelled" in errors_on(
               changeset
             ).status
    end

    test "valid changeset with status 'active'" do
      attrs = %{
        ticket_tier_id: Ecto.ULID.generate(),
        user_id: Ecto.ULID.generate(),
        created_by_id: Ecto.ULID.generate(),
        quantity: 1,
        status: "active"
      }

      changeset = TicketReservation.changeset(%TicketReservation{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset with status 'fulfilled'" do
      attrs = %{
        ticket_tier_id: Ecto.ULID.generate(),
        user_id: Ecto.ULID.generate(),
        created_by_id: Ecto.ULID.generate(),
        quantity: 1,
        status: "fulfilled"
      }

      changeset = TicketReservation.changeset(%TicketReservation{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset with status 'cancelled'" do
      attrs = %{
        ticket_tier_id: Ecto.ULID.generate(),
        user_id: Ecto.ULID.generate(),
        created_by_id: Ecto.ULID.generate(),
        quantity: 1,
        status: "cancelled"
      }

      changeset = TicketReservation.changeset(%TicketReservation{}, attrs)
      assert changeset.valid?
    end

    test "invalid changeset when expires_at is in the past" do
      attrs = %{
        ticket_tier_id: Ecto.ULID.generate(),
        user_id: Ecto.ULID.generate(),
        created_by_id: Ecto.ULID.generate(),
        quantity: 1,
        expires_at: DateTime.add(DateTime.utc_now(), -3600, :second)
      }

      changeset = TicketReservation.changeset(%TicketReservation{}, attrs)
      refute changeset.valid?
      assert "must be in the future" in errors_on(changeset).expires_at
    end

    test "valid changeset when expires_at is in the future" do
      attrs = %{
        ticket_tier_id: Ecto.ULID.generate(),
        user_id: Ecto.ULID.generate(),
        created_by_id: Ecto.ULID.generate(),
        quantity: 1,
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      }

      changeset = TicketReservation.changeset(%TicketReservation{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset when expires_at is nil" do
      attrs = %{
        ticket_tier_id: Ecto.ULID.generate(),
        user_id: Ecto.ULID.generate(),
        created_by_id: Ecto.ULID.generate(),
        quantity: 1,
        expires_at: nil
      }

      changeset = TicketReservation.changeset(%TicketReservation{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset with fulfilled_at timestamp" do
      attrs = %{
        ticket_tier_id: Ecto.ULID.generate(),
        user_id: Ecto.ULID.generate(),
        created_by_id: Ecto.ULID.generate(),
        quantity: 1,
        status: "fulfilled",
        fulfilled_at: DateTime.utc_now()
      }

      changeset = TicketReservation.changeset(%TicketReservation{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset with cancelled_at timestamp" do
      attrs = %{
        ticket_tier_id: Ecto.ULID.generate(),
        user_id: Ecto.ULID.generate(),
        created_by_id: Ecto.ULID.generate(),
        quantity: 1,
        status: "cancelled",
        cancelled_at: DateTime.utc_now()
      }

      changeset = TicketReservation.changeset(%TicketReservation{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset with ticket_order_id" do
      attrs = %{
        ticket_tier_id: Ecto.ULID.generate(),
        user_id: Ecto.ULID.generate(),
        created_by_id: Ecto.ULID.generate(),
        quantity: 1,
        ticket_order_id: Ecto.ULID.generate()
      }

      changeset = TicketReservation.changeset(%TicketReservation{}, attrs)
      assert changeset.valid?
    end

    test "default status is 'active'" do
      reservation = %TicketReservation{}
      assert reservation.status == "active"
    end
  end
end
