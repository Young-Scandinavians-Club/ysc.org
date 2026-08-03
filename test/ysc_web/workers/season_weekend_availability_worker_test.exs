defmodule YscWeb.Workers.SeasonWeekendAvailabilityWorkerTest do
  use Ysc.DataCase, async: false

  import Ecto.Query
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  alias Ysc.Bookings.Season
  alias Ysc.Repo
  alias YscWeb.Workers.SeasonWeekendAvailabilityWorker

  setup do
    seed_canonical_seasons!()
    :ok
  end

  defp tahoe_season(name) do
    Repo.get_by!(Season, name: name, property: :tahoe)
  end

  describe "run/1" do
    test "sends the winter weekend email and marks the season once the window opens" do
      recipient = user_fixture()

      assert :ok = SeasonWeekendAvailabilityWorker.run(~D[2026-10-01])

      idempotency_key =
        "tahoe_winter_weekend_available_#{tahoe_season("Winter").id}_2026_#{recipient.id}"

      assert Repo.get_by(Ysc.Messages.MessageIdempotency,
               idempotency_key: idempotency_key
             )

      winter = tahoe_season("Winter")
      assert winter.weekend_notification_sent_cycle_year == 2026
      assert winter.weekend_notification_sent_at != nil
      assert winter.weekend_notification_recipient_count == 1
    end

    test "does not send again for the same cycle year" do
      recipient = user_fixture()

      assert :ok = SeasonWeekendAvailabilityWorker.run(~D[2026-10-01])
      sent_at_first = tahoe_season("Winter").weekend_notification_sent_at

      assert :ok = SeasonWeekendAvailabilityWorker.run(~D[2026-10-05])

      winter = tahoe_season("Winter")
      assert winter.weekend_notification_sent_at == sent_at_first

      idempotency_key =
        "tahoe_winter_weekend_available_#{winter.id}_2026_#{recipient.id}"

      assert Repo.aggregate(
               from(m in Ysc.Messages.MessageIdempotency,
                 where: m.idempotency_key == ^idempotency_key
               ),
               :count
             ) == 1
    end

    test "does not send while the winter window hasn't opened yet" do
      user_fixture()

      assert :ok = SeasonWeekendAvailabilityWorker.run(~D[2026-08-02])

      winter = tahoe_season("Winter")
      assert winter.weekend_notification_sent_cycle_year == nil
      assert winter.weekend_notification_sent_at == nil
    end

    test "sends the summer buyout email once winter's own advance window reaches the first summer weekend" do
      recipient = user_fixture()

      assert :ok = SeasonWeekendAvailabilityWorker.run(~D[2027-04-10])

      summer = tahoe_season("Summer")
      assert summer.weekend_notification_sent_cycle_year == 2027
      assert summer.weekend_notification_recipient_count == 1

      idempotency_key =
        "tahoe_summer_buyout_available_#{summer.id}_2027_#{recipient.id}"

      assert Repo.get_by(Ysc.Messages.MessageIdempotency,
               idempotency_key: idempotency_key
             )
    end

    test "summer stays closed while deep in winter even though summer has no advance limit of its own" do
      user_fixture()

      assert :ok = SeasonWeekendAvailabilityWorker.run(~D[2027-01-15])

      summer = tahoe_season("Summer")
      assert summer.weekend_notification_sent_cycle_year == nil
    end

    test "only notifies users with event_notifications enabled and an active state" do
      opted_in = user_fixture()

      opted_out = user_fixture()

      {:ok, _} =
        Ysc.Accounts.update_notification_preferences(opted_out, %{
          event_notifications: false,
          account_notifications: true
        })

      inactive = user_fixture(%{state: :suspended})

      assert :ok = SeasonWeekendAvailabilityWorker.run(~D[2026-10-01])

      winter = tahoe_season("Winter")
      assert winter.weekend_notification_recipient_count == 1

      assert Repo.get_by(Ysc.Messages.MessageIdempotency,
               idempotency_key:
                 "tahoe_winter_weekend_available_#{winter.id}_2026_#{opted_in.id}"
             )

      refute Repo.get_by(Ysc.Messages.MessageIdempotency,
               idempotency_key:
                 "tahoe_winter_weekend_available_#{winter.id}_2026_#{opted_out.id}"
             )

      refute Repo.get_by(Ysc.Messages.MessageIdempotency,
               idempotency_key:
                 "tahoe_winter_weekend_available_#{winter.id}_2026_#{inactive.id}"
             )
    end
  end
end
