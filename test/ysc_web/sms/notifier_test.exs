defmodule YscWeb.Sms.NotifierTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Repo
  alias YscWeb.Sms.Notifier

  @valid_phone "12065551234"

  describe "schedule_sms/5" do
    test "returns error when phone number is invalid" do
      assert {:error, :invalid_phone_number} =
               Notifier.schedule_sms(
                 "000",
                 "idem-#{System.unique_integer([:positive])}",
                 "booking_checkin_reminder",
                 %{},
                 nil
               )
    end

    test "schedules when user_id is nil and phone is valid" do
      assert {:ok, %Oban.Job{}} =
               Notifier.schedule_sms(
                 @valid_phone,
                 "idem-guest-#{System.unique_integer([:positive])}",
                 "booking_checkin_reminder",
                 %{first_name: "x"},
                 nil
               )
    end

    test "returns error when user has no phone on file" do
      user = user_fixture()

      {:ok, user_no_phone} =
        user
        |> Ecto.Changeset.change(%{
          phone_number: nil,
          account_notifications_sms: true
        })
        |> Repo.update()

      assert {:error, :no_phone_number} =
               Notifier.schedule_sms(
                 nil,
                 "idem-nophone-#{System.unique_integer([:positive])}",
                 "booking_checkin_reminder",
                 %{},
                 user_no_phone.id
               )
    end

    test "returns error when user disabled account SMS notifications" do
      user =
        user_fixture(%{
          phone_number: unique_user_phone(),
          account_notifications_sms: false
        })

      assert {:error, :notifications_disabled} =
               Notifier.schedule_sms(
                 @valid_phone,
                 "idem-off-#{System.unique_integer([:positive])}",
                 "booking_checkin_reminder",
                 %{},
                 user.id
               )
    end
  end

  describe "send_sms_idempotent/5" do
    test "returns error when template is unknown" do
      assert {:error, msg} =
               Notifier.send_sms_idempotent(
                 @valid_phone,
                 "idem-unknown-#{System.unique_integer([:positive])}",
                 "not_a_real_template",
                 %{},
                 nil
               )

      assert msg =~ "not_a_real_template"
    end

    test "returns error when phone is invalid" do
      assert {:error, :invalid_phone_number} =
               Notifier.send_sms_idempotent(
                 "bad",
                 "idem-bad-#{System.unique_integer([:positive])}",
                 "two_factor_verification",
                 %{code: "123456"},
                 nil
               )
    end
  end

  describe "get_template_module/1" do
    test "returns nil for unknown template" do
      assert Notifier.get_template_module(
               "unknown_template_" <> Integer.to_string(System.unique_integer())
             ) ==
               nil
    end

    test "returns module for registered template" do
      assert Notifier.get_template_module("phone_verification") ==
               YscWeb.Sms.PhoneVerification
    end
  end
end
