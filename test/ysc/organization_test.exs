defmodule Ysc.OrganizationTest do
  use ExUnit.Case, async: true

  alias Ysc.Organization

  test "mailing_address_lines/0 includes organization name and new address" do
    assert Organization.mailing_address_lines() == [
             "Young Scandinavians Club",
             "28 Geary St",
             "Ste 650 #304",
             "San Francisco, CA 94108"
           ]
  end

  test "mailing_address_street_lines/0 excludes organization name" do
    assert Organization.mailing_address_street_lines() == [
             "28 Geary St",
             "Ste 650 #304",
             "San Francisco, CA 94108"
           ]
  end

  test "mailing_address_plain_text/0 joins lines with newlines" do
    assert Organization.mailing_address_plain_text() ==
             "Young Scandinavians Club\n28 Geary St\nSte 650 #304\nSan Francisco, CA 94108"
  end
end
