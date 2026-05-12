defmodule YscWeb.Emails.HelpersTest do
  use ExUnit.Case, async: true

  alias YscWeb.Emails.Helpers

  describe "origin/0 and absolute_url/1" do
    test "absolute_url appends a path to the endpoint origin" do
      origin = YscWeb.Endpoint.url()
      assert Helpers.origin() == origin
      id = "evt-id-123"
      assert Helpers.absolute_url("/events/#{id}") == origin <> "/events/#{id}"
    end
  end

  describe "member_greeting_name/1" do
    test "returns Valued Member for nil, blank, or whitespace-only" do
      assert Helpers.member_greeting_name(nil) == "Valued Member"
      assert Helpers.member_greeting_name("") == "Valued Member"
      assert Helpers.member_greeting_name("   ") == "Valued Member"
    end

    test "returns trimmed name for binary input" do
      assert Helpers.member_greeting_name("  Anna  ") == "Anna"
    end

    test "reads :first_name from maps and structs" do
      assert Helpers.member_greeting_name(%{first_name: "Bo"}) == "Bo"
      assert Helpers.member_greeting_name(%{first_name: nil}) == "Valued Member"
      assert Helpers.member_greeting_name(%{first_name: ""}) == "Valued Member"
    end

    test "defaults for maps without first_name" do
      assert Helpers.member_greeting_name(%{}) == "Valued Member"
    end

    test "defaults for unexpected types" do
      assert Helpers.member_greeting_name(:atom) == "Valued Member"
    end
  end
end
