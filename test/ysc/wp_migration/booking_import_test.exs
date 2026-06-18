defmodule Ysc.WpMigration.BookingImportTest do
  use ExUnit.Case, async: true

  alias Ysc.WpMigration.BookingImport

  describe "resolve_wp_user_id/4" do
    test "prefers _mphb_user_id from customer post map" do
      assert BookingImport.resolve_wp_user_id(
               %{"255" => "1234"},
               %{"eva@example.com" => "9999"},
               "255",
               "eva@example.com"
             ) == "1234"
    end

    test "falls back to mphb_email when customer post has no user id" do
      assert BookingImport.resolve_wp_user_id(
               %{},
               %{"evabackman123@gmail.com" => "5678"},
               "255",
               "evabackman123@gmail.com"
             ) == "5678"
    end

    test "does not treat customer post id as wp user id" do
      assert BookingImport.resolve_wp_user_id(%{}, %{}, "255", nil) == nil
    end

    test "normalizes email case when matching" do
      assert BookingImport.resolve_wp_user_id(
               %{},
               %{"evabackman123@gmail.com" => "5678"},
               "255",
               "EvaBackman123@Gmail.com"
             ) == "5678"
    end
  end

  describe "resolve_migrated_user_id/2" do
    test "does not use wp_customer_user_id when it equals wp_customer_post_id" do
      row = %{
        "guest_email" => nil,
        "wp_customer_user_id" => "30",
        "wp_customer_post_id" => "30"
      }

      assert BookingImport.resolve_migrated_user_id(row, %{
               "30" => "wrong-user-id"
             }) ==
               nil
    end
  end

  describe "guest_is_booking_user?/4" do
    test "matches case-insensitively with surrounding whitespace" do
      assert BookingImport.guest_is_booking_user?(
               " Eva ",
               "Backman",
               "eva",
               "backman "
             )

      refute BookingImport.guest_is_booking_user?(
               "Eva",
               "Smith",
               "eva",
               "backman"
             )
    end
  end

  describe "backup booking samples" do
    setup do
      path =
        Path.expand(
          "../../fixtures/wp_migration/booking_backup_samples.json",
          __DIR__
        )

      %{samples: path |> File.read!() |> Jason.decode!()}
    end

    test "customer post ids from backup are not valid wp user ids on their own",
         %{
           samples: samples
         } do
      for sample <- samples do
        wrong_user =
          BookingImport.resolve_wp_user_id(
            %{},
            %{},
            sample["wp_customer_post_id"],
            nil
          )

        assert wrong_user == nil,
               "customer post #{sample["wp_customer_post_id"]} must not resolve without email"
      end
    end

    test "email map resolves the real booker for backup samples", %{
      samples: samples
    } do
      for sample <- samples do
        email = BookingImport.normalize_email(sample["guest_email"])

        wp_user_id =
          BookingImport.resolve_wp_user_id(
            %{},
            %{email => "expected-wp-user"},
            sample["wp_customer_post_id"],
            sample["guest_email"]
          )

        assert wp_user_id == "expected-wp-user",
               "failed for booking #{sample["wp_booking_id"]}: #{sample["description"]}"
      end
    end
  end
end
