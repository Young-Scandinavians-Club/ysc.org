defmodule YscWeb.AdminMembershipHelpersTest do
  use ExUnit.Case, async: true

  alias YscWeb.AdminMembershipHelpers

  describe "membership_type_label/2" do
    test "short style for check-in desks" do
      assert AdminMembershipHelpers.membership_type_label(nil, :short) ==
               "Member"

      assert AdminMembershipHelpers.membership_type_label(:lifetime, :short) ==
               "Lifetime"

      assert AdminMembershipHelpers.membership_type_label("lifetime", :short) ==
               "Lifetime"

      assert AdminMembershipHelpers.membership_type_label(:single, :short) ==
               "Single"

      assert AdminMembershipHelpers.membership_type_label("family", :short) ==
               "Family"

      assert AdminMembershipHelpers.membership_type_label(:corporate, :short) ==
               "Corporate"

      assert AdminMembershipHelpers.membership_type_label("corporate", :short) ==
               "Corporate"

      assert AdminMembershipHelpers.membership_type_label(123, :short) ==
               "Member"
    end

    test "full style for scanner and detail panels" do
      assert AdminMembershipHelpers.membership_type_label(nil, :full) ==
               "Unknown"

      assert AdminMembershipHelpers.membership_type_label(:lifetime, :full) ==
               "Lifetime Membership"

      assert AdminMembershipHelpers.membership_type_label(:single, :full) ==
               "Single Membership"

      assert AdminMembershipHelpers.membership_type_label(:family, :full) ==
               "Family Membership"

      assert AdminMembershipHelpers.membership_type_label(:corporate, :full) ==
               "Corporate Membership"

      assert AdminMembershipHelpers.membership_type_label(123, :full) ==
               "Membership"
    end
  end

  describe "registration_form_membership_type_label/1" do
    test "returns short label from registration form membership type" do
      user = %{registration_form: %{membership_type: :family}}

      assert AdminMembershipHelpers.registration_form_membership_type_label(
               user
             ) ==
               "Family"
    end

    test "returns N/A when registration form or membership type is missing" do
      assert AdminMembershipHelpers.registration_form_membership_type_label(%{}) ==
               "N/A"

      assert AdminMembershipHelpers.registration_form_membership_type_label(%{
               registration_form: %{membership_type: nil}
             }) == "N/A"
    end
  end
end
