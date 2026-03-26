defmodule YscWeb.Workers.EmailNotifierMailerFailureTest do
  @moduledoc """
  Serial tests that swap `Ysc.Mailer` adapter — must run with `async: false`.
  Covers EmailNotifier.perform/1 when `Ysc.Messages.run_send_message_idempotent/2` returns an error.
  """
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures

  alias YscWeb.Workers.EmailNotifier

  setup do
    prev = Application.get_env(:ysc, Ysc.Mailer) || []

    on_exit(fn ->
      Application.put_env(:ysc, Ysc.Mailer, prev)
    end)

    {:ok, mailer_config: prev}
  end

  describe "perform/1 when Mailer.deliver fails" do
    test "returns error tuple and does not create idempotency row", %{
      mailer_config: mailer_config
    } do
      Application.put_env(
        :ysc,
        Ysc.Mailer,
        Keyword.merge(mailer_config, adapter: Ysc.Test.FailingSwooshAdapter)
      )

      user = user_fixture()
      key = "notifier_fail_#{System.unique_integer()}"

      params = %{
        first_name: "John",
        booking: %{
          reference_id: "REF-FAIL",
          property: "Tahoe",
          checkin_date: "Jan 1, 2024",
          checkout_date: "Jan 5, 2024",
          guests_count: 2,
          children_count: 0,
          booking_mode: "Room Booking",
          room_names: "Room 1",
          nights: 4,
          is_buyout: false,
          booking_mode_raw: "room"
        },
        total_amount: "$100.00",
        booking_date: "Dec 25, 2023",
        booking_url: "http://example.com/bookings/123"
      }

      assert {:error, "failed to send email"} =
               perform_job(EmailNotifier, %{
                 "recipient" => user.email,
                 "idempotency_key" => key,
                 "subject" => "Mailer Failure",
                 "template" => "booking_confirmation",
                 "params" => params,
                 "text_body" => "Text body",
                 "user_id" => user.id,
                 "category" => "bookings"
               })

      assert Ysc.Repo.get_by(Ysc.Messages.MessageIdempotency,
               idempotency_key: key
             ) == nil
    end
  end
end
