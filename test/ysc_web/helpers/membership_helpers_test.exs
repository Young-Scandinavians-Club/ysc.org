defmodule YscWeb.MembershipHelpersTest do
  use ExUnit.Case, async: true

  defmodule MembershipStub do
    @moduledoc false
    defstruct [:start_date]
  end

  alias YscWeb.MembershipHelpers

  describe "build_membership_qr_details/1" do
    test "returns nil when assigns do not match" do
      assert MembershipHelpers.build_membership_qr_details(%{}) == nil

      assert MembershipHelpers.build_membership_qr_details(%{current_user: %{}}) ==
               nil
    end

    test "returns nil for lifetime label and member_since from awarded_at" do
      user = %{first_name: "U", inserted_at: ~U[2021-01-01 00:00:00Z]}
      membership = %{type: :lifetime, awarded_at: ~D[2019-06-15]}

      assert %{
               type_label: "Lifetime Membership",
               plan_type: :lifetime,
               member_since: ~D[2019-06-15],
               renewal_date: nil,
               is_sub_account: false,
               primary_name: nil
             } ==
               MembershipHelpers.build_membership_qr_details(%{
                 current_user: user,
                 current_membership: membership,
                 is_sub_account: false,
                 primary_user: nil
               })
    end

    test "uses Active Membership label when plan type is unknown" do
      user = %{first_name: "U", inserted_at: ~U[2022-02-02 00:00:00Z]}

      assert %{
               type_label: "Active Membership",
               plan_type: nil,
               member_since: ~U[2022-02-02 00:00:00Z],
               renewal_date: nil,
               is_sub_account: false,
               primary_name: nil
             } ==
               MembershipHelpers.build_membership_qr_details(%{
                 current_user: user,
                 current_membership: %{},
                 is_sub_account: false,
                 primary_user: nil
               })
    end

    test "formats plan id from plan struct as membership label" do
      user = %{first_name: "U", inserted_at: ~U[2021-01-01 00:00:00Z]}
      membership = %{plan: %{id: :family}}

      assert %{
               type_label: "Family Membership",
               plan_type: :family,
               member_since: ~U[2021-01-01 00:00:00Z],
               renewal_date: nil,
               is_sub_account: false,
               primary_name: nil
             } ==
               MembershipHelpers.build_membership_qr_details(%{
                 current_user: user,
                 current_membership: membership,
                 is_sub_account: false,
                 primary_user: nil
               })
    end

    test "uses start_date when membership is a non-subscription struct" do
      user = %{first_name: "U", inserted_at: ~U[2021-01-01 00:00:00Z]}

      membership = %MembershipStub{start_date: ~U[2023-05-10 12:00:00Z]}

      assert %{
               type_label: "Active Membership",
               member_since: ~U[2023-05-10 12:00:00Z],
               is_sub_account: false,
               primary_name: nil
             } =
               MembershipHelpers.build_membership_qr_details(%{
                 current_user: user,
                 current_membership: membership,
                 is_sub_account: false,
                 primary_user: nil
               })
    end

    test "includes primary account name for sub-accounts" do
      user = %{first_name: "U", inserted_at: ~U[2021-01-01 00:00:00Z]}
      membership = %{type: :lifetime}
      primary = %{first_name: "Pat", last_name: "Primary"}

      assert %{primary_name: "Pat Primary", is_sub_account: true} =
               MembershipHelpers.build_membership_qr_details(%{
                 current_user: user,
                 current_membership: membership,
                 is_sub_account: true,
                 primary_user: primary
               })
    end
  end
end
