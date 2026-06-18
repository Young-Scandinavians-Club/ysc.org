defmodule Ysc.WpMigration.IgnoredAccountsTest do
  use ExUnit.Case, async: true

  alias Ysc.WpMigration.IgnoredAccounts

  describe "ignored_user?/1" do
    test "matches legacy WordPress test accounts by email" do
      assert IgnoredAccounts.ignored_user?(%{
               "email" => "help@getflywheel.com",
               "display_name" => "help@getflywheel.com"
             })

      assert IgnoredAccounts.ignored_user?(%{
               "email" => "webtech@ysc.org",
               "display_name" => "admin"
             })

      assert IgnoredAccounts.ignored_user?(%{
               "email" => "joshua+ysc@jbrost.com",
               "display_name" => "JoshTestUser"
             })

      assert IgnoredAccounts.ignored_user?(%{
               "email" => "dev@myworks.software",
               "display_name" => "dev@myworks.software"
             })
    end

    test "matches JoshTestUser display name" do
      assert IgnoredAccounts.ignored_user?(%{
               "email" => "other@example.com",
               "display_name" => "JoshTestUser"
             })
    end

    test "does not match real members" do
      refute IgnoredAccounts.ignored_user?(%{
               "email" => "backman93@gmail.com",
               "display_name" => "Johan Backman"
             })
    end
  end

  describe "reject_users/1" do
    test "removes ignored users from export rows" do
      users = [
        %{"wp_user_id" => "1", "email" => "member@example.com"},
        %{
          "wp_user_id" => "2",
          "email" => "webtech@ysc.org",
          "display_name" => "admin"
        }
      ]

      assert [%{"wp_user_id" => "1"}] = IgnoredAccounts.reject_users(users)
    end
  end
end
