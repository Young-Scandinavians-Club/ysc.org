defmodule Ysc.Accounts.UserNotifierTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Accounts.UserNotifier

  describe "deliver_passkey_added_notification/2" do
    test "schedules email with correct parameters" do
      user = user_fixture()
      device_name = "Chrome on macOS"

      job = UserNotifier.deliver_passkey_added_notification(user, device_name)

      assert job
      assert job.args["recipient"] == user.email
      assert job.args["subject"] == "New Passkey Added to Your YSC Account"
      assert job.args["template"] == "passkey_added"

      assert job.args["params"]["first_name"] ==
               String.capitalize(user.first_name)

      assert job.args["params"]["device_name"] == device_name
      assert job.args["user_id"] == user.id
    end
  end

  describe "deliver_password_changed_notification/1" do
    test "schedules email with correct parameters" do
      user = user_fixture()

      job = UserNotifier.deliver_password_changed_notification(user)

      assert job
      assert job.args["recipient"] == user.email
      assert job.args["subject"] == "Your YSC Password Has Been Changed"
      assert job.args["template"] == "password_changed"

      assert job.args["params"]["first_name"] ==
               String.capitalize(user.first_name)

      assert job.args["user_id"] == user.id
    end
  end

  describe "deliver_email_changed_notification/3" do
    test "schedules email to old email address with correct parameters" do
      user = user_fixture()
      old_email = user.email
      new_email = "new_email@example.com"

      job =
        UserNotifier.deliver_email_changed_notification(
          user,
          old_email,
          new_email
        )

      assert job
      assert job.args["recipient"] == old_email
      assert job.args["subject"] == "Your YSC Email Has Been Changed"
      assert job.args["template"] == "email_changed"

      assert job.args["params"]["first_name"] ==
               String.capitalize(user.first_name)

      assert job.args["params"]["new_email"] == new_email
      assert job.args["user_id"] == user.id
    end
  end
end
