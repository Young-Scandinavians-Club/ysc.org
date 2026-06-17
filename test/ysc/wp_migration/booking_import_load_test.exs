defmodule Ysc.WpMigration.BookingImportLoadTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Bookings.Booking
  alias Ysc.Bookings.BookingGuest
  alias Ysc.Repo
  alias Ysc.WpMigration.BookingImport

  @fixture_path Path.expand(
                  "../../fixtures/wp_migration/booking_backup_samples.json",
                  __DIR__
                )

  setup do
    eva =
      user_fixture(%{
        email: "evabackman123@gmail.com",
        first_name: "Eva",
        last_name: "Backman"
      })

    wrong_user =
      user_fixture(%{
        email: "bobbysfca@aol.com",
        first_name: "Bobby",
        last_name: "Wrong"
      })

    sample =
      @fixture_path
      |> File.read!()
      |> Jason.decode!()
      |> Enum.find(&(&1["wp_booking_id"] == "57158"))

    %{eva: eva, wrong_user: wrong_user, sample: sample}
  end

  describe "resolve_migrated_user_id/2" do
    test "prefers guest email over incorrect wp_customer_user_id", %{
      eva: eva,
      wrong_user: wrong_user,
      sample: sample
    } do
      user_map = %{"255" => wrong_user.id}

      assert BookingImport.resolve_migrated_user_id(sample, user_map) == eva.id
    end

    test "rejects wp_customer_user_id when it equals customer post id", %{
      wrong_user: wrong_user
    } do
      samples =
        @fixture_path |> File.read!() |> Jason.decode!()

      johan_sample = Enum.find(samples, &(&1["wp_booking_id"] == "63752"))

      user_map = %{"30" => wrong_user.id}

      assert BookingImport.resolve_migrated_user_id(johan_sample, user_map) ==
               nil
    end
  end

  describe "migrated booking repair" do
    test "fixes booking member and guest flag on re-run", %{
      eva: eva,
      wrong_user: wrong_user,
      sample: sample
    } do
      ref_id = "MIG-WP-#{sample["wp_booking_id"]}"

      booking =
        %Booking{}
        |> Ecto.Changeset.change(%{
          reference_id: ref_id,
          checkin_date: ~D[2025-03-09],
          checkout_date: ~D[2025-03-13],
          guests_count: 2,
          children_count: 0,
          property: :tahoe,
          booking_mode: :room,
          status: :complete,
          total_price: Money.new(:USD, 600),
          user_id: wrong_user.id
        })
        |> Repo.insert!()

      %BookingGuest{}
      |> BookingGuest.changeset(%{
        booking_id: booking.id,
        first_name: "Eva",
        last_name: "Backman",
        is_booking_user: false,
        order_index: 0
      })
      |> Repo.insert!()

      user_map = %{"255" => wrong_user.id}
      correct_user_id = BookingImport.resolve_migrated_user_id(sample, user_map)
      assert correct_user_id == eva.id

      booking = Repo.preload(booking, :booking_guests)

      {:ok, fixed} =
        booking
        |> Ecto.Changeset.change(user_id: correct_user_id)
        |> Repo.update()

      [guest] = fixed.booking_guests |> Repo.preload(:booking)

      is_booking_user =
        BookingImport.guest_is_booking_user?(
          guest.first_name,
          guest.last_name,
          eva.first_name,
          eva.last_name
        )

      {:ok, guest} =
        guest
        |> BookingGuest.changeset(%{is_booking_user: is_booking_user})
        |> Repo.update()

      assert fixed.user_id == eva.id
      assert guest.is_booking_user == true
    end
  end
end
