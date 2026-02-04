defmodule Ysc.EmailConfigTest do
  use ExUnit.Case, async: true

  alias Ysc.EmailConfig

  describe "from_email/0" do
    test "returns configured from email or default" do
      email = EmailConfig.from_email()
      assert is_binary(email)
      assert email != ""
    end
  end

  describe "from_name/0" do
    test "returns configured from name or default" do
      name = EmailConfig.from_name()
      assert is_binary(name)
      assert name != ""
    end
  end

  describe "contact_email/0" do
    test "returns configured contact email or default" do
      email = EmailConfig.contact_email()
      assert is_binary(email)
      assert email != ""
    end
  end

  describe "admin_email/0" do
    test "returns configured admin email or default" do
      email = EmailConfig.admin_email()
      assert is_binary(email)
      assert email != ""
    end
  end

  describe "membership_email/0" do
    test "returns configured membership email or default" do
      email = EmailConfig.membership_email()
      assert is_binary(email)
      assert email != ""
    end
  end

  describe "board_email/0" do
    test "returns configured board email or default" do
      email = EmailConfig.board_email()
      assert is_binary(email)
      assert email != ""
    end
  end

  describe "volunteer_email/0" do
    test "returns configured volunteer email or default" do
      email = EmailConfig.volunteer_email()
      assert is_binary(email)
      assert email != ""
    end
  end

  describe "tahoe_email/0" do
    test "returns configured tahoe email or default" do
      email = EmailConfig.tahoe_email()
      assert is_binary(email)
      assert email != ""
    end
  end

  describe "clear_lake_email/0" do
    test "returns configured clear lake email or default" do
      email = EmailConfig.clear_lake_email()
      assert is_binary(email)
      assert email != ""
    end
  end
end
