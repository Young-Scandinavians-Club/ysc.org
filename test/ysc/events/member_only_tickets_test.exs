defmodule Ysc.Events.MemberOnlyTicketsTest do
  use ExUnit.Case, async: true

  alias Ysc.Events.MemberOnlyTickets, as: Policy

  defp tier(id, opts \\ []) do
    %{
      id: id,
      type: Keyword.get(opts, :type, "paid"),
      member_only: Keyword.get(opts, :member_only, false)
    }
  end

  describe "event_limit/1" do
    test "single members get a limit of one" do
      assert Policy.event_limit(:single) == 1
    end

    test "family and lifetime members are unlimited" do
      assert Policy.event_limit(:family) == :unlimited
      assert Policy.event_limit(:lifetime) == :unlimited
    end

    test "no plan type means not eligible" do
      assert Policy.event_limit(nil) == 0
    end

    test "unknown plan types are permissive" do
      assert Policy.event_limit(:some_future_plan) == :unlimited
    end
  end

  describe "member_only?/1" do
    test "true only when flagged and not a donation tier" do
      assert Policy.member_only?(tier("a", member_only: true))
      refute Policy.member_only?(tier("b", member_only: false))

      refute Policy.member_only?(tier("c", member_only: true, type: "donation"))
    end

    test "supports string keys and nil" do
      assert Policy.member_only?(%{"id" => "a", "member_only" => true})
      refute Policy.member_only?(nil)
    end
  end

  describe "selected_count/2" do
    setup do
      tiers = [
        tier("mo1", member_only: true),
        tier("mo2", member_only: true),
        tier("reg", member_only: false)
      ]

      %{tiers: tiers}
    end

    test "sums quantities only across member-only tiers", %{tiers: tiers} do
      selected = %{"mo1" => 1, "mo2" => 2, "reg" => 5}
      assert Policy.selected_count(selected, tiers) == 3
    end

    test "ignores non-positive and non-integer quantities", %{tiers: tiers} do
      selected = %{"mo1" => 0, "mo2" => "not-a-number"}
      assert Policy.selected_count(selected, tiers) == 0
    end
  end

  describe "can_add?/5" do
    setup do
      tiers = [tier("mo1", member_only: true), tier("mo2", member_only: true)]
      %{tiers: tiers}
    end

    test "regular tiers are always allowed", %{tiers: tiers} do
      assert Policy.can_add?(tier("reg"), %{"reg" => 9}, tiers, 0, 0)
    end

    test "single member can add the first member-only ticket then is blocked",
         %{tiers: tiers} do
      assert Policy.can_add?(hd(tiers), %{}, tiers, 1, 0)
      refute Policy.can_add?(Enum.at(tiers, 1), %{"mo1" => 1}, tiers, 1, 0)
    end

    test "already-owned member-only tickets count against the limit", %{
      tiers: tiers
    } do
      refute Policy.can_add?(hd(tiers), %{}, tiers, 1, 1)
    end

    test "family/lifetime members are never blocked", %{tiers: tiers} do
      assert Policy.can_add?(hd(tiers), %{"mo1" => 4}, tiers, :unlimited, 3)
    end

    test "ineligible members cannot add any", %{tiers: tiers} do
      refute Policy.can_add?(hd(tiers), %{}, tiers, 0, 0)
    end
  end

  describe "validate_selection/4" do
    setup do
      tiers = [tier("mo1", member_only: true), tier("mo2", member_only: true)]
      %{tiers: tiers}
    end

    test "ok when no member-only tiers selected", %{tiers: tiers} do
      assert Policy.validate_selection(%{"reg" => 2}, tiers, 0, 0) == :ok
    end

    test "not eligible when plan limit is zero", %{tiers: tiers} do
      assert Policy.validate_selection(%{"mo1" => 1}, tiers, 0, 0) ==
               {:error, :member_only_not_eligible}
    end

    test "single member may take exactly one across tiers", %{tiers: tiers} do
      assert Policy.validate_selection(%{"mo1" => 1}, tiers, 1, 0) == :ok

      assert Policy.validate_selection(%{"mo1" => 1, "mo2" => 1}, tiers, 1, 0) ==
               {:error, :member_only_limit_exceeded}
    end

    test "counts already-owned tickets", %{tiers: tiers} do
      assert Policy.validate_selection(%{"mo1" => 1}, tiers, 1, 1) ==
               {:error, :member_only_limit_exceeded}
    end

    test "unlimited plans always pass", %{tiers: tiers} do
      assert Policy.validate_selection(
               %{"mo1" => 3, "mo2" => 2},
               tiers,
               :unlimited,
               10
             ) == :ok
    end
  end
end
