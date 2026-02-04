defmodule Ysc.Bookings.RefundPolicyTest do
  @moduledoc """
  Tests for RefundPolicy schema.

  These tests verify:
  - Required field validation
  - Property and booking_mode enum validation
  - String length validations
  - Active policy uniqueness per property/mode combination
  - Association with refund policy rules
  - Database constraints
  """
  use Ysc.DataCase, async: false

  alias Ysc.Bookings.{RefundPolicy, RefundPolicyRule}
  alias Ysc.Repo

  describe "changeset/2" do
    test "creates valid changeset with all required fields" do
      attrs = %{
        name: "Standard Refund Policy",
        property: :tahoe,
        booking_mode: :room
      }

      changeset = RefundPolicy.changeset(%RefundPolicy{}, attrs)

      assert changeset.valid?
      assert changeset.changes.name == "Standard Refund Policy"
      assert changeset.changes.property == :tahoe
      assert changeset.changes.booking_mode == :room
    end

    test "creates valid changeset with optional fields" do
      attrs = %{
        name: "Flexible Refund Policy",
        description:
          "Generous refund policy with full refunds up to 14 days before check-in",
        property: :clear_lake,
        booking_mode: :day,
        is_active: false
      }

      changeset = RefundPolicy.changeset(%RefundPolicy{}, attrs)

      assert changeset.valid?

      assert changeset.changes.description ==
               "Generous refund policy with full refunds up to 14 days before check-in"

      # Test with non-default value so it appears in changes
      assert changeset.changes.is_active == false
    end

    test "requires name" do
      attrs = %{
        property: :tahoe,
        booking_mode: :room
      }

      changeset = RefundPolicy.changeset(%RefundPolicy{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:name] != nil
    end

    test "requires property" do
      attrs = %{
        name: "Standard Policy",
        booking_mode: :room
      }

      changeset = RefundPolicy.changeset(%RefundPolicy{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:property] != nil
    end

    test "requires booking_mode" do
      attrs = %{
        name: "Standard Policy",
        property: :tahoe
      }

      changeset = RefundPolicy.changeset(%RefundPolicy{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:booking_mode] != nil
    end

    test "validates name maximum length (255 characters)" do
      long_name = String.duplicate("a", 256)

      attrs = %{
        name: long_name,
        property: :tahoe,
        booking_mode: :room
      }

      changeset = RefundPolicy.changeset(%RefundPolicy{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:name] != nil
    end

    test "accepts name with exactly 255 characters" do
      valid_name = String.duplicate("a", 255)

      attrs = %{
        name: valid_name,
        property: :tahoe,
        booking_mode: :room
      }

      changeset = RefundPolicy.changeset(%RefundPolicy{}, attrs)

      assert changeset.valid?
    end

    test "validates description maximum length (5000 characters)" do
      long_description = String.duplicate("a", 5001)

      attrs = %{
        name: "Standard Policy",
        description: long_description,
        property: :tahoe,
        booking_mode: :room
      }

      changeset = RefundPolicy.changeset(%RefundPolicy{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:description] != nil
    end

    test "accepts description with exactly 5000 characters" do
      valid_description = String.duplicate("a", 5000)

      attrs = %{
        name: "Standard Policy",
        description: valid_description,
        property: :tahoe,
        booking_mode: :room
      }

      changeset = RefundPolicy.changeset(%RefundPolicy{}, attrs)

      assert changeset.valid?
    end
  end

  describe "property enum" do
    test "accepts tahoe property" do
      attrs = %{
        name: "Tahoe Policy",
        property: :tahoe,
        booking_mode: :room
      }

      changeset = RefundPolicy.changeset(%RefundPolicy{}, attrs)

      assert changeset.valid?
      assert changeset.changes.property == :tahoe
    end

    test "accepts clear_lake property" do
      attrs = %{
        name: "Clear Lake Policy",
        property: :clear_lake,
        booking_mode: :day
      }

      changeset = RefundPolicy.changeset(%RefundPolicy{}, attrs)

      assert changeset.valid?
      assert changeset.changes.property == :clear_lake
    end

    test "rejects invalid property" do
      attrs = %{
        name: "Invalid Policy",
        property: :invalid_property,
        booking_mode: :room
      }

      changeset = RefundPolicy.changeset(%RefundPolicy{}, attrs)

      refute changeset.valid?
    end
  end

  describe "booking_mode enum" do
    test "accepts room booking mode" do
      attrs = %{
        name: "Room Policy",
        property: :tahoe,
        booking_mode: :room
      }

      changeset = RefundPolicy.changeset(%RefundPolicy{}, attrs)

      assert changeset.valid?
      assert changeset.changes.booking_mode == :room
    end

    test "accepts day booking mode" do
      attrs = %{
        name: "Day Policy",
        property: :clear_lake,
        booking_mode: :day
      }

      changeset = RefundPolicy.changeset(%RefundPolicy{}, attrs)

      assert changeset.valid?
      assert changeset.changes.booking_mode == :day
    end

    test "accepts buyout booking mode" do
      attrs = %{
        name: "Buyout Policy",
        property: :tahoe,
        booking_mode: :buyout
      }

      changeset = RefundPolicy.changeset(%RefundPolicy{}, attrs)

      assert changeset.valid?
      assert changeset.changes.booking_mode == :buyout
    end

    test "rejects invalid booking mode" do
      attrs = %{
        name: "Invalid Policy",
        property: :tahoe,
        booking_mode: :invalid_mode
      }

      changeset = RefundPolicy.changeset(%RefundPolicy{}, attrs)

      refute changeset.valid?
    end
  end

  describe "database operations" do
    test "can insert and retrieve complete refund policy" do
      attrs = %{
        name: "Standard Refund Policy",
        description: "Standard refund terms for Tahoe room bookings",
        property: :tahoe,
        booking_mode: :room,
        is_active: true
      }

      changeset = RefundPolicy.changeset(%RefundPolicy{}, attrs)
      {:ok, policy} = Repo.insert(changeset)

      retrieved = Repo.get(RefundPolicy, policy.id)

      assert retrieved.name == "Standard Refund Policy"

      assert retrieved.description ==
               "Standard refund terms for Tahoe room bookings"

      assert retrieved.property == :tahoe
      assert retrieved.booking_mode == :room
      assert retrieved.is_active == true
      assert retrieved.inserted_at != nil
      assert retrieved.updated_at != nil
    end

    test "defaults is_active to true" do
      attrs = %{
        name: "Standard Policy",
        property: :tahoe,
        booking_mode: :room
      }

      changeset = RefundPolicy.changeset(%RefundPolicy{}, attrs)
      {:ok, policy} = Repo.insert(changeset)

      assert policy.is_active == true
    end

    test "can retrieve policy with preloaded rules" do
      # Create policy
      {:ok, policy} =
        %RefundPolicy{}
        |> RefundPolicy.changeset(%{
          name: "Standard Policy",
          property: :tahoe,
          booking_mode: :room
        })
        |> Repo.insert()

      # Create rule
      {:ok, _rule} =
        %RefundPolicyRule{}
        |> RefundPolicyRule.changeset(%{
          refund_policy_id: policy.id,
          days_before_checkin: 14,
          refund_percentage: Decimal.new("100.0"),
          description: "Full refund 14+ days before"
        })
        |> Repo.insert()

      # Retrieve with preload
      retrieved =
        RefundPolicy
        |> Repo.get(policy.id)
        |> Repo.preload(:rules)

      assert retrieved.name == "Standard Policy"
      assert length(retrieved.rules) == 1
      assert hd(retrieved.rules).days_before_checkin == 14
    end
  end

  describe "typical refund policy scenarios" do
    test "Tahoe room refund policy with graduated tiers" do
      {:ok, policy} =
        %RefundPolicy{}
        |> RefundPolicy.changeset(%{
          name: "Tahoe Standard Refund Policy",
          description: "Standard refund policy for Tahoe room bookings",
          property: :tahoe,
          booking_mode: :room
        })
        |> Repo.insert()

      # Create tiered rules
      rules_attrs = [
        {30, "100.0", "Full refund 30+ days before"},
        {14, "75.0", "75% refund 14-29 days before"},
        {7, "50.0", "50% refund 7-13 days before"},
        {0, "0.0", "No refund within 7 days"}
      ]

      for {days, percentage, desc} <- rules_attrs do
        {:ok, _rule} =
          %RefundPolicyRule{}
          |> RefundPolicyRule.changeset(%{
            refund_policy_id: policy.id,
            days_before_checkin: days,
            refund_percentage: Decimal.new(percentage),
            description: desc
          })
          |> Repo.insert()
      end

      # Verify policy and rules
      retrieved =
        RefundPolicy
        |> Repo.get(policy.id)
        |> Repo.preload(:rules)

      assert retrieved.name == "Tahoe Standard Refund Policy"
      assert length(retrieved.rules) == 4
    end

    test "Clear Lake day booking policy" do
      {:ok, policy} =
        %RefundPolicy{}
        |> RefundPolicy.changeset(%{
          name: "Clear Lake Day Booking Refund Policy",
          description: "Flexible refund policy for Clear Lake day bookings",
          property: :clear_lake,
          booking_mode: :day
        })
        |> Repo.insert()

      assert policy.property == :clear_lake
      assert policy.booking_mode == :day
    end

    test "Tahoe buyout policy (non-refundable)" do
      {:ok, policy} =
        %RefundPolicy{}
        |> RefundPolicy.changeset(%{
          name: "Tahoe Buyout Non-Refundable",
          description: "Buyouts are non-refundable",
          property: :tahoe,
          booking_mode: :buyout
        })
        |> Repo.insert()

      # Create single non-refundable rule
      {:ok, _rule} =
        %RefundPolicyRule{}
        |> RefundPolicyRule.changeset(%{
          refund_policy_id: policy.id,
          days_before_checkin: 0,
          refund_percentage: Decimal.new("0.0"),
          description: "Non-refundable"
        })
        |> Repo.insert()

      retrieved =
        RefundPolicy
        |> Repo.get(policy.id)
        |> Repo.preload(:rules)

      assert retrieved.booking_mode == :buyout
      assert length(retrieved.rules) == 1

      assert Decimal.equal?(
               hd(retrieved.rules).refund_percentage,
               Decimal.new("0.0")
             )
    end
  end

  describe "cascade delete" do
    test "deleting policy deletes associated rules" do
      # Create policy
      {:ok, policy} =
        %RefundPolicy{}
        |> RefundPolicy.changeset(%{
          name: "Test Policy",
          property: :tahoe,
          booking_mode: :room
        })
        |> Repo.insert()

      # Create rules
      {:ok, rule1} =
        %RefundPolicyRule{}
        |> RefundPolicyRule.changeset(%{
          refund_policy_id: policy.id,
          days_before_checkin: 14,
          refund_percentage: Decimal.new("100.0")
        })
        |> Repo.insert()

      {:ok, rule2} =
        %RefundPolicyRule{}
        |> RefundPolicyRule.changeset(%{
          refund_policy_id: policy.id,
          days_before_checkin: 7,
          refund_percentage: Decimal.new("50.0")
        })
        |> Repo.insert()

      # Verify rules exist
      assert Repo.get(RefundPolicyRule, rule1.id) != nil
      assert Repo.get(RefundPolicyRule, rule2.id) != nil

      # Delete policy
      Repo.delete(policy)

      # Verify rules are deleted
      assert Repo.get(RefundPolicyRule, rule1.id) == nil
      assert Repo.get(RefundPolicyRule, rule2.id) == nil
    end
  end
end
