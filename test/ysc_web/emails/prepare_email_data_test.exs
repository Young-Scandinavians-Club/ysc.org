defmodule YscWeb.Emails.PrepareEmailDataTest do
  @moduledoc """
  Targeted tests for `prepare_email_data/1` (and related helpers) on booking and
  expense report email modules. Improves branch coverage for validation paths,
  preload fallbacks, and formatting.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  import Ecto.Query

  alias Ysc.{Accounts, ExpenseReports, Ledgers, Repo}
  alias Ysc.Accounts.User
  alias Ysc.Bookings.{Booking, BookingRoom, PendingRefund, Room}

  alias Ysc.ExpenseReports.{
    ExpenseReport,
    ExpenseReportIncomeItem,
    ExpenseReportItem
  }

  alias Ysc.Ledgers

  alias YscWeb.Emails.{
    BookingCancellationConfirmation,
    BookingCheckinReminder,
    BookingCheckoutReminder,
    BookingConfirmation,
    BookingRefundPending,
    BookingRefundProcessed,
    ExpenseReportConfirmation,
    ExpenseReportTreasurerNotification
  }

  describe "BookingRefundPending.prepare_email_data/3" do
    setup do
      user = user_fixture()
      booking = booking_fixture(%{user_id: user.id})

      {:ok, booking} =
        booking
        |> Ecto.Changeset.change(%{status: :complete})
        |> Repo.update()

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id:
            "pi_refund_pending_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(100, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      {:ok, pending_refund} =
        %PendingRefund{}
        |> PendingRefund.changeset(%{
          booking_id: booking.id,
          payment_id: payment.id,
          policy_refund_amount: Money.div!(booking.total_price, 2),
          status: :pending,
          cancellation_reason: "Change of plans"
        })
        |> Repo.insert()

      %{
        user: user,
        booking: booking,
        payment: payment,
        pending_refund: pending_refund
      }
    end

    test "raises when pending_refund is nil", %{
      booking: booking,
      payment: payment
    } do
      assert_raise ArgumentError, "Pending refund cannot be nil", fn ->
        Ysc.Test.Invoke.call(BookingRefundPending, :prepare_email_data, [
          nil,
          booking,
          payment
        ])
      end
    end

    test "raises when booking is nil", %{pending_refund: pr, payment: payment} do
      assert_raise ArgumentError, "Booking cannot be nil", fn ->
        Ysc.Test.Invoke.call(BookingRefundPending, :prepare_email_data, [
          pr,
          nil,
          payment
        ])
      end
    end

    test "raises when booking id is not found", %{
      pending_refund: pr,
      payment: payment
    } do
      missing =
        struct!(Booking, %{
          id: Ecto.ULID.generate(),
          user_id: Ecto.ULID.generate(),
          checkin_date: ~D[2025-06-02],
          checkout_date: ~D[2025-06-05],
          property: :tahoe,
          booking_mode: :buyout,
          reference_id: "BKG-MISS",
          guests_count: 2,
          total_price: Money.new(100, :USD)
        })

      assert_raise ArgumentError, fn ->
        Ysc.Test.Invoke.call(BookingRefundPending, :prepare_email_data, [
          pr,
          missing,
          payment
        ])
      end
    end

    test "reloads booking when user is not loaded", %{
      pending_refund: pr,
      booking: booking,
      payment: payment
    } do
      bare = Repo.get!(Booking, booking.id)

      data = BookingRefundPending.prepare_email_data(pr, bare, payment)

      assert data.first_name ==
               booking
               |> Repo.preload(:user)
               |> Map.fetch!(:user)
               |> Map.fetch!(:first_name)

      assert data.pending_refund.refund_percentage != nil
    end

    test "uses default cancellation reason when nil", %{
      booking: booking,
      payment: payment,
      pending_refund: pr
    } do
      {:ok, pr} =
        pr
        |> Ecto.Changeset.change(%{cancellation_reason: nil})
        |> Repo.update()

      data = BookingRefundPending.prepare_email_data(pr, booking, payment)
      assert data.pending_refund.cancellation_reason == "Booking cancelled"
    end

    test "payment nil omits refund percentage and shows N/A for payment amount",
         %{
           pending_refund: pr,
           booking: booking
         } do
      data = BookingRefundPending.prepare_email_data(pr, booking, nil)
      assert data.pending_refund.refund_percentage == nil
      assert data.payment.amount == "N/A"
      assert data.payment.reference_id == "N/A"
    end
  end

  describe "BookingCheckinReminder.prepare_email_data/1" do
    setup do
      user = user_fixture()

      Repo.update_all(from(u in User, where: u.id == ^user.id),
        set: [first_name: nil]
      )

      user = Repo.get!(User, user.id)

      booking = booking_fixture(%{user_id: user.id})
      booking = Repo.preload(booking, [:user, :rooms])
      %{user: user, booking: booking}
    end

    test "raises when booking is nil" do
      assert_raise ArgumentError, "Booking cannot be nil", fn ->
        Ysc.Test.Invoke.call(BookingCheckinReminder, :prepare_email_data, [nil])
      end
    end

    test "raises when booking id is nil", %{booking: booking} do
      assert_raise ArgumentError, fn ->
        Ysc.Test.Invoke.call(BookingCheckinReminder, :prepare_email_data, [
          %{booking | id: nil}
        ])
      end
    end

    test "raises when booking is not in database" do
      b =
        struct!(Booking, %{
          id: Ecto.ULID.generate(),
          user_id: Ecto.ULID.generate(),
          checkin_date: ~D[2025-07-07],
          checkout_date: ~D[2025-07-10],
          property: :tahoe,
          booking_mode: :buyout,
          reference_id: "BKG-X",
          guests_count: 2,
          children_count: nil,
          total_price: Money.new(300, :USD)
        })

      assert_raise ArgumentError, fn ->
        Ysc.Test.Invoke.call(BookingCheckinReminder, :prepare_email_data, [b])
      end
    end

    test "uses Valued Member and children_count 0 when missing", %{
      booking: booking
    } do
      data = BookingCheckinReminder.prepare_email_data(booking)
      assert data.first_name == "Valued Member"
      assert data.children_count == 0
    end

    test "reloads when associations are not preloaded", %{booking: booking} do
      bare = Repo.get!(Booking, booking.id)
      data = BookingCheckinReminder.prepare_email_data(bare)
      assert data.booking_reference_id == booking.reference_id
    end

    test "clear_lake property names and subject", %{user: user} do
      booking =
        booking_fixture(%{user_id: user.id, property: :clear_lake})
        |> Repo.preload([:user, :rooms])

      data = BookingCheckinReminder.prepare_email_data(booking)
      assert data.property_name == "Clear Lake"
      assert data.property == "clear_lake"
      assert data.property_address =~ "Kelseyville"

      assert BookingCheckinReminder.get_subject(booking) =~ "Clear Lake"
    end

    test "includes joined room names for room bookings", %{user: user} do
      {:ok, room} =
        %Room{}
        |> Room.changeset(%{
          name: "Sunrise Loft",
          property: :tahoe,
          capacity_max: 4,
          is_active: true
        })
        |> Repo.insert()

      {:ok, booking} =
        %Booking{}
        |> Booking.changeset(
          %{
            user_id: user.id,
            checkin_date: ~D[2025-08-04],
            checkout_date: ~D[2025-08-06],
            property: :tahoe,
            booking_mode: :room,
            guests_count: 2,
            total_price: Money.new(150, :USD)
          },
          skip_validation: true
        )
        |> Repo.insert()

      {:ok, _} =
        %BookingRoom{booking_id: booking.id, room_id: room.id}
        |> Repo.insert()

      booking =
        booking
        |> Repo.preload([:user, :rooms])

      data = BookingCheckinReminder.prepare_email_data(booking)
      assert data.room_names =~ "Sunrise Loft"
      assert data.booking_mode == "Room Booking"
      assert data.is_buyout == false
    end

    test "buyout booking sets is_buyout", %{user: user} do
      booking =
        booking_fixture(%{user_id: user.id, booking_mode: :buyout})
        |> Repo.preload([:user, :rooms])

      assert BookingCheckinReminder.prepare_email_data(booking).is_buyout ==
               true
    end
  end

  describe "BookingCheckoutReminder.prepare_email_data/1" do
    setup do
      user = user_fixture()
      booking = booking_fixture(%{user_id: user.id, property: :clear_lake})
      %{booking: Repo.preload(booking, [:user, :rooms])}
    end

    test "raises when booking is nil" do
      assert_raise ArgumentError, "Booking cannot be nil", fn ->
        Ysc.Test.Invoke.call(BookingCheckoutReminder, :prepare_email_data, [nil])
      end
    end

    test "clear_lake checkout data", %{booking: booking} do
      data = BookingCheckoutReminder.prepare_email_data(booking)
      assert data.property_name == "Clear Lake"
      assert data.property == "clear_lake"
      assert BookingCheckoutReminder.get_subject() =~ "Checkout Reminder"
    end

    test "reloads when user is not preloaded", %{booking: booking} do
      bare = Repo.get!(Booking, booking.id)
      data = BookingCheckoutReminder.prepare_email_data(bare)
      assert data.booking_reference_id == booking.reference_id
    end

    test "raises when booking id is nil", %{booking: booking} do
      assert_raise ArgumentError, fn ->
        Ysc.Test.Invoke.call(BookingCheckoutReminder, :prepare_email_data, [
          %{booking | id: nil}
        ])
      end
    end

    test "includes cabin master contact when assigned for Tahoe", %{
      booking: booking
    } do
      _master =
        user_fixture()
        |> Ecto.Changeset.change(%{
          board_position: :tahoe_cabin_master,
          phone_number: "+15551234567"
        })
        |> Repo.update!()

      tahoe_booking =
        booking_fixture(%{user_id: booking.user_id, property: :tahoe})
        |> Repo.preload([:user, :rooms])

      data = BookingCheckoutReminder.prepare_email_data(tahoe_booking)
      assert data.cabin_master_email == Ysc.EmailConfig.tahoe_email()
      assert data.cabin_master_name != nil
      assert data.cabin_master_phone != nil
    end
  end

  describe "BookingConfirmation.prepare_email_data/1" do
    setup do
      user = user_fixture()

      booking =
        booking_fixture(%{user_id: user.id}) |> Repo.preload([:user, :rooms])

      %{user: user, booking: booking}
    end

    test "raises when booking is nil" do
      assert_raise ArgumentError, "Booking cannot be nil", fn ->
        Ysc.Test.Invoke.call(BookingConfirmation, :prepare_email_data, [nil])
      end
    end

    test "prepare_email_data formats booking_date in Pacific time and money", %{
      booking: booking
    } do
      data = BookingConfirmation.prepare_email_data(booking)
      assert data.booking_date =~ ~r/P(S|D)T$/
      assert data.total_amount =~ "$"

      assert BookingConfirmation.booking_url(booking.id) =~
               "/bookings/#{booking.id}/receipt"

      assert BookingConfirmation.get_subject() =~ "confirmed"
    end

    test "room names and day booking mode description", %{user: user} do
      {:ok, room} =
        %Room{}
        |> Room.changeset(%{
          name: "Pine",
          property: :tahoe,
          capacity_max: 3,
          is_active: true
        })
        |> Repo.insert()

      {:ok, booking} =
        %Booking{}
        |> Booking.changeset(
          %{
            user_id: user.id,
            checkin_date: ~D[2025-09-01],
            checkout_date: ~D[2025-09-01],
            property: :tahoe,
            booking_mode: :day,
            guests_count: 1,
            total_price: Money.new(40, :USD)
          },
          skip_validation: true
        )
        |> Repo.insert()

      {:ok, _} =
        %BookingRoom{booking_id: booking.id, room_id: room.id}
        |> Repo.insert()

      booking = booking |> Repo.preload([:user, :rooms])

      data = BookingConfirmation.prepare_email_data(booking)
      assert data.booking.room_names =~ "Pine"
      assert data.booking.booking_mode == "Day Booking"
      assert data.booking.is_buyout == false
    end
  end

  describe "ExpenseReportConfirmation.prepare_email_data/1" do
    setup do
      user = user_fixture()

      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{
            "routing_number" => "021000021",
            "account_number" => "1234567890"
          },
          user
        )

      event = Ysc.EventsFixtures.event_fixture(%{organizer_id: user.id})

      {:ok, report} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "status" => "draft",
            "purpose" => "Supplies",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "event_id" => event.id,
            "expense_items" => [
              %{
                "date" => "2024-06-10",
                "vendor" => "Vendor",
                "description" => "Paint",
                "amount" => "25.00",
                "receipt_s3_path" => "receipts/r1.pdf"
              }
            ],
            "income_items" => [
              %{
                "date" => "2024-06-11",
                "description" => "Deposit",
                "amount" => "5.00",
                "proof_s3_path" => "proofs/p1.pdf"
              }
            ]
          },
          user
        )

      report =
        Repo.preload(report, [
          :user,
          :expense_items,
          :income_items,
          :event,
          :bank_account
        ])

      %{user: user, report: report, event: event}
    end

    test "raises when expense report is nil" do
      assert_raise ArgumentError, "Expense report cannot be nil", fn ->
        Ysc.Test.Invoke.call(ExpenseReportConfirmation, :prepare_email_data, [
          nil
        ])
      end
    end

    test "raises when id is missing" do
      assert_raise ArgumentError, fn ->
        Ysc.Test.Invoke.call(ExpenseReportConfirmation, :prepare_email_data, [
          %ExpenseReport{
            id: nil,
            user_id: Ecto.ULID.generate()
          }
        ])
      end
    end

    test "raises when expense report does not exist" do
      assert_raise ArgumentError, fn ->
        Ysc.Test.Invoke.call(ExpenseReportConfirmation, :prepare_email_data, [
          %ExpenseReport{
            id: Ecto.ULID.generate(),
            user_id: Ecto.ULID.generate()
          }
        ])
      end
    end

    test "full data includes event, bank account, and line flags", %{
      report: report
    } do
      data = ExpenseReportConfirmation.prepare_email_data(report)

      assert data.expense_report.event.title
      assert data.expense_report.bank_account.last_4 =~ ~r/\d/
      [exp_item] = data.expense_report.expense_items
      [inc_item] = data.expense_report.income_items
      assert exp_item.has_receipt == true
      assert inc_item.has_proof == true
      assert data.expense_report_url =~ "/expensereport/#{report.id}/success"
    end

    test "reloads when associations missing", %{report: report} do
      bare = Repo.get!(ExpenseReport, report.id)
      data = ExpenseReportConfirmation.prepare_email_data(bare)
      assert data.expense_report.purpose == "Supplies"
    end

    test "custom reimbursement string is capitalized", %{user: user} do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1098765432"},
          user
        )

      {:ok, report} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "status" => "draft",
            "purpose" => "Other",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id
          },
          user
        )

      Repo.update_all(
        from(r in ExpenseReport, where: r.id == ^report.id),
        set: [reimbursement_method: "venmo"]
      )

      report = Repo.get!(ExpenseReport, report.id)
      data = ExpenseReportConfirmation.prepare_email_data(report)
      assert data.expense_report.reimbursement_method == "Venmo"
    end
  end

  describe "ExpenseReportTreasurerNotification.prepare_email_data/1" do
    setup do
      user =
        user_fixture(%{
          last_name: "TreasurerCase"
        })

      Repo.update_all(from(u in User, where: u.id == ^user.id),
        set: [first_name: nil]
      )

      user = Repo.get!(User, user.id)

      {:ok, _} =
        Accounts.update_billing_address(user, %{
          "address" => "99 Oak Ave",
          "city" => "Oakland",
          "region" => "CA",
          "postal_code" => "94601",
          "country" => "US"
        })

      user = Repo.get!(User, user.id)

      {:ok, report} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "status" => "draft",
            "purpose" => "Board meeting",
            "reimbursement_method" => "check"
          },
          user
        )

      report =
        report
        |> Repo.preload([
          :user,
          :expense_items,
          :income_items,
          :event,
          :bank_account,
          :address
        ])

      %{report: report}
    end

    test "builds user name from email and includes mailing address", %{
      report: report
    } do
      data = ExpenseReportTreasurerNotification.prepare_email_data(report)

      assert data.user.name == "TreasurerCase"
      assert data.user.email == report.user.email
      assert data.expense_report.address.city == "Oakland"
      assert data.admin_url =~ "/admin/expense_reports/#{report.id}"
    end

    test "reloads from id only", %{report: report} do
      bare = Repo.get!(ExpenseReport, report.id)
      data = ExpenseReportTreasurerNotification.prepare_email_data(bare)
      assert data.expense_report.purpose == "Board meeting"
    end

    test "raises when expense report is nil" do
      assert_raise ArgumentError, fn ->
        Ysc.Test.Invoke.call(
          ExpenseReportTreasurerNotification,
          :prepare_email_data,
          [nil]
        )
      end
    end

    test "formats bank_transfer reimbursement and unknown method fallback", %{
      report: report
    } do
      Repo.update_all(from(r in ExpenseReport, where: r.id == ^report.id),
        set: [reimbursement_method: "bank_transfer"]
      )

      report =
        Repo.get!(ExpenseReport, report.id)
        |> Repo.preload([
          :user,
          :expense_items,
          :income_items,
          :event,
          :bank_account,
          :address
        ])

      data = ExpenseReportTreasurerNotification.prepare_email_data(report)
      assert data.expense_report.reimbursement_method == "Bank Transfer"

      Repo.update_all(from(r in ExpenseReport, where: r.id == ^report.id),
        set: [reimbursement_method: "custom_method"]
      )

      report =
        Repo.get!(ExpenseReport, report.id)
        |> Repo.preload([
          :user,
          :expense_items,
          :income_items,
          :event,
          :bank_account,
          :address
        ])

      data = ExpenseReportTreasurerNotification.prepare_email_data(report)
      assert data.expense_report.reimbursement_method == "Custom_method"
    end

    test "marks receipt and proof flags on line items", %{report: report} do
      %ExpenseReportItem{}
      |> ExpenseReportItem.changeset(%{
        expense_report_id: report.id,
        date: Date.utc_today(),
        vendor: "Acme",
        description: "Supplies",
        amount: Money.new(1000, :USD),
        receipt_s3_path: "receipts/a.pdf"
      })
      |> Repo.insert!()

      %ExpenseReportIncomeItem{}
      |> ExpenseReportIncomeItem.changeset(%{
        expense_report_id: report.id,
        date: Date.utc_today(),
        description: "Rebate",
        amount: Money.new(500, :USD),
        proof_s3_path: "proofs/b.pdf"
      })
      |> Repo.insert!()

      report =
        Repo.get!(ExpenseReport, report.id)
        |> Repo.preload([
          :user,
          :expense_items,
          :income_items,
          :event,
          :bank_account,
          :address
        ])

      data = ExpenseReportTreasurerNotification.prepare_email_data(report)

      [exp_row] = data.expense_report.expense_items
      [inc_row] = data.expense_report.income_items

      assert exp_row.has_receipt == true
      assert inc_row.has_proof == true
    end
  end

  describe "BookingCancellationConfirmation.prepare_email_data/5" do
    setup do
      user = user_fixture()
      booking = booking_fixture(%{user_id: user.id}) |> Repo.preload(:user)
      %{booking: booking}
    end

    test "builds cancellation email data", %{booking: booking} do
      data = BookingCancellationConfirmation.prepare_email_data(booking)

      assert data.first_name ==
               (booking.user.first_name || "Valued Member")

      assert data.booking.reference_id == booking.reference_id
      assert data.cancellation.reason == "No reason provided"
      assert data.booking_url =~ "/bookings/#{booking.id}/receipt"
      assert data.refund.is_pending == false
    end

    test "passes custom reason and pending refund flag", %{booking: booking} do
      data =
        BookingCancellationConfirmation.prepare_email_data(
          booking,
          nil,
          nil,
          true,
          "Travel changed"
        )

      assert data.cancellation.reason == "Travel changed"
      assert data.refund.is_pending == true
    end

    test "raises when booking is nil" do
      assert_raise ArgumentError, "Booking cannot be nil", fn ->
        Ysc.Test.Invoke.call(
          BookingCancellationConfirmation,
          :prepare_email_data,
          [nil]
        )
      end
    end

    test "raises when booking id is not found", %{booking: booking} do
      missing =
        struct!(Booking, %{
          id: Ecto.ULID.generate(),
          user_id: booking.user_id,
          checkin_date: booking.checkin_date,
          checkout_date: booking.checkout_date,
          property: booking.property,
          booking_mode: booking.booking_mode,
          reference_id: "BKG-MISS",
          guests_count: 2,
          total_price: Money.new(100, :USD)
        })

      assert_raise ArgumentError, ~r/Booking not found/, fn ->
        Ysc.Test.Invoke.call(
          BookingCancellationConfirmation,
          :prepare_email_data,
          [missing]
        )
      end
    end

    test "reloads booking when user association is not loaded", %{
      booking: booking
    } do
      bare = Repo.get!(Booking, booking.id)

      data = BookingCancellationConfirmation.prepare_email_data(bare)

      assert data.first_name ==
               (booking.user.first_name || "Valued Member")

      assert data.booking.reference_id == booking.reference_id
    end

    test "includes refund and payment details when provided", %{booking: orig} do
      user = orig.user

      booking =
        booking_fixture(%{user_id: user.id, property: :clear_lake})
        |> Repo.preload(:user)

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(200, :USD),
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id: "pi_bcc_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(100, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      refund_amount = Money.new(50, :USD)

      data =
        BookingCancellationConfirmation.prepare_email_data(
          booking,
          payment,
          refund_amount,
          false,
          "Schedule conflict"
        )

      assert data.booking.property == "Clear Lake"
      assert data.payment.reference_id == payment.reference_id
      assert data.payment.amount =~ "200"
      assert data.refund.amount =~ "50"
      assert data.refund.is_pending == false
      assert data.cancellation.reason == "Schedule conflict"
    end

    test "omits refund line when refund amount is zero or not positive", %{
      booking: booking
    } do
      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: booking.user_id,
          amount: Money.new(200, :USD),
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id:
            "pi_zero_ref_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(100, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      data =
        BookingCancellationConfirmation.prepare_email_data(
          booking,
          payment,
          Money.new(0, :USD),
          false,
          nil
        )

      assert data.refund.amount == nil
    end

    test "uses Valued Member when user first_name is nil", %{booking: booking} do
      Repo.update_all(from(u in User, where: u.id == ^booking.user_id),
        set: [first_name: nil]
      )

      booking = booking |> Repo.preload([:user], force: true)

      data = BookingCancellationConfirmation.prepare_email_data(booking)
      assert data.first_name == "Valued Member"
    end

    test "formats unknown property atom as capitalized string", %{
      booking: booking
    } do
      booking = %{booking | property: :sequoia}

      data = BookingCancellationConfirmation.prepare_email_data(booking)

      assert data.booking.property == "Sequoia"
    end

    test "formats non-atom property as string via to_string/1", %{
      booking: booking
    } do
      booking = %{booking | property: "custom_site"}

      data = BookingCancellationConfirmation.prepare_email_data(booking)

      assert data.booking.property == "custom_site"
    end
  end

  describe "BookingRefundProcessed.prepare_email_data/3" do
    setup do
      user = user_fixture()

      booking =
        booking_fixture(%{user_id: user.id, property: :tahoe})

      {:ok, booking} =
        booking
        |> Ecto.Changeset.change(%{status: :complete})
        |> Repo.update()

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(20_000, :USD),
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id: "pi_brp_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(640, :USD),
          description: "Booking",
          property: :tahoe,
          payment_method_id: nil
        })

      {:ok, {refund, _, _}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(10_000, :USD),
          reason: "Guest cancellation",
          external_refund_id: "re_brp_#{System.unique_integer([:positive])}"
        })

      %{
        user: user,
        booking: booking,
        payment: payment,
        refund: refund
      }
    end

    test "raises when refund is nil", %{booking: booking, payment: payment} do
      assert_raise ArgumentError, "Refund cannot be nil", fn ->
        Ysc.Test.Invoke.call(BookingRefundProcessed, :prepare_email_data, [
          nil,
          booking,
          payment
        ])
      end
    end

    test "raises when booking is nil", %{refund: refund, payment: payment} do
      assert_raise ArgumentError, "Booking cannot be nil", fn ->
        Ysc.Test.Invoke.call(BookingRefundProcessed, :prepare_email_data, [
          refund,
          nil,
          payment
        ])
      end
    end

    test "reloads booking when user is not preloaded", %{
      refund: refund,
      booking: booking,
      payment: payment
    } do
      bare = Repo.get!(Booking, booking.id)

      data = BookingRefundProcessed.prepare_email_data(refund, bare, payment)

      assert data.booking.reference_id == booking.reference_id
      assert data.refund.amount =~ "$"
    end

    test "uses N/A for payment when payment is nil", %{
      refund: refund,
      booking: booking
    } do
      data = BookingRefundProcessed.prepare_email_data(refund, booking, nil)

      assert data.payment.amount == "N/A"
      assert data.payment.reference_id == "N/A"
    end

    test "uses default refund reason copy when reason field is nil", %{
      refund: refund,
      booking: booking,
      payment: payment
    } do
      {:ok, refund} =
        refund
        |> Ecto.Changeset.change(%{reason: nil})
        |> Repo.update()

      data = BookingRefundProcessed.prepare_email_data(refund, booking, payment)
      assert data.refund.reason == "Refund processed"
    end

    test "formats refund date as N/A when inserted_at is nil", %{
      refund: refund,
      booking: booking,
      payment: payment
    } do
      refund = %{refund | inserted_at: nil}

      data = BookingRefundProcessed.prepare_email_data(refund, booking, payment)

      assert data.refund.refund_date == "N/A"
      assert data.refund_date == "N/A"
    end
  end
end
