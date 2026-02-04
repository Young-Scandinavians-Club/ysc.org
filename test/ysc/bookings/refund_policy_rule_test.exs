defmodule Ysc.Bookings.RefundPolicyRuleTest do
  @moduledoc """
  Tests for RefundPolicyRule schema.

  These tests verify:
  - Required field validation
  - Days before check-in validation (non-negative)
  - Refund percentage validation (0-100)
  - Priority field
  - Foreign key constraints
  - Decimal precision handling
  - Rule ordering
  """
  use Ysc.DataCase, async: true

  alias Ysc.Bookings.{RefundPolicy, RefundPolicyRule}
  alias Ysc.Repo

  setup do
    # Create a refund policy for testing rules
    {:ok, policy} =
      %RefundPolicy{}
      |> RefundPolicy.changeset(%{
        name: "Test Policy",
        property: :tahoe,
        booking_mode: :room
      })
      |> Repo.insert()

    %{policy: policy}
  end

  describe "changeset/2" do
    test "creates valid changeset with all required fields", %{policy: policy} do
      attrs = %{
        refund_policy_id: policy.id,
        days_before_checkin: 14,
        refund_percentage: Decimal.new("100.0")
      }

      changeset = RefundPolicyRule.changeset(%RefundPolicyRule{}, attrs)

      assert changeset.valid?
      assert changeset.changes.days_before_checkin == 14
      assert changeset.changes.refund_percentage == Decimal.new("100.0")
    end

    test "creates valid changeset with optional fields", %{policy: policy} do
      attrs = %{
        refund_policy_id: policy.id,
        days_before_checkin: 7,
        refund_percentage: Decimal.new("50.0"),
        description: "50% refund 7-13 days before check-in",
        priority: 1
      }

      changeset = RefundPolicyRule.changeset(%RefundPolicyRule{}, attrs)

      assert changeset.valid?

      assert changeset.changes.description ==
               "50% refund 7-13 days before check-in"

      assert changeset.changes.priority == 1
    end

    test "requires days_before_checkin" do
      attrs = %{
        refund_policy_id: Ecto.ULID.generate(),
        refund_percentage: Decimal.new("100.0")
      }

      changeset = RefundPolicyRule.changeset(%RefundPolicyRule{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:days_before_checkin] != nil
    end

    test "requires refund_percentage" do
      attrs = %{
        refund_policy_id: Ecto.ULID.generate(),
        days_before_checkin: 14
      }

      changeset = RefundPolicyRule.changeset(%RefundPolicyRule{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:refund_percentage] != nil
    end

    test "requires refund_policy_id" do
      attrs = %{
        days_before_checkin: 14,
        refund_percentage: Decimal.new("100.0")
      }

      changeset = RefundPolicyRule.changeset(%RefundPolicyRule{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:refund_policy_id] != nil
    end

    test "validates description maximum length (500 characters)", %{
      policy: policy
    } do
      long_description = String.duplicate("a", 501)

      attrs = %{
        refund_policy_id: policy.id,
        days_before_checkin: 14,
        refund_percentage: Decimal.new("100.0"),
        description: long_description
      }

      changeset = RefundPolicyRule.changeset(%RefundPolicyRule{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:description] != nil
    end

    test "accepts description with exactly 500 characters", %{policy: policy} do
      valid_description = String.duplicate("a", 500)

      attrs = %{
        refund_policy_id: policy.id,
        days_before_checkin: 14,
        refund_percentage: Decimal.new("100.0"),
        description: valid_description
      }

      changeset = RefundPolicyRule.changeset(%RefundPolicyRule{}, attrs)

      assert changeset.valid?
    end
  end

  describe "days_before_checkin validation" do
    test "accepts zero days before checkin", %{policy: policy} do
      attrs = %{
        refund_policy_id: policy.id,
        days_before_checkin: 0,
        refund_percentage: Decimal.new("0.0")
      }

      changeset = RefundPolicyRule.changeset(%RefundPolicyRule{}, attrs)

      assert changeset.valid?
    end

    test "accepts positive days before checkin", %{policy: policy} do
      attrs = %{
        refund_policy_id: policy.id,
        days_before_checkin: 30,
        refund_percentage: Decimal.new("100.0")
      }

      changeset = RefundPolicyRule.changeset(%RefundPolicyRule{}, attrs)

      assert changeset.valid?
    end

    test "rejects negative days before checkin", %{policy: policy} do
      attrs = %{
        refund_policy_id: policy.id,
        days_before_checkin: -1,
        refund_percentage: Decimal.new("50.0")
      }

      changeset = RefundPolicyRule.changeset(%RefundPolicyRule{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:days_before_checkin] != nil
    end

    test "accepts large days before checkin values", %{policy: policy} do
      attrs = %{
        refund_policy_id: policy.id,
        days_before_checkin: 365,
        refund_percentage: Decimal.new("100.0")
      }

      changeset = RefundPolicyRule.changeset(%RefundPolicyRule{}, attrs)

      assert changeset.valid?
    end
  end

  describe "refund_percentage validation" do
    test "accepts 0% refund", %{policy: policy} do
      attrs = %{
        refund_policy_id: policy.id,
        days_before_checkin: 0,
        refund_percentage: Decimal.new("0.0")
      }

      changeset = RefundPolicyRule.changeset(%RefundPolicyRule{}, attrs)

      assert changeset.valid?
    end

    test "accepts 100% refund", %{policy: policy} do
      attrs = %{
        refund_policy_id: policy.id,
        days_before_checkin: 30,
        refund_percentage: Decimal.new("100.0")
      }

      changeset = RefundPolicyRule.changeset(%RefundPolicyRule{}, attrs)

      assert changeset.valid?
    end

    test "accepts partial refund percentages", %{policy: policy} do
      partial_percentages = [
        "25.0",
        "50.0",
        "75.0",
        "33.33",
        "66.67"
      ]

      for percentage <- partial_percentages do
        attrs = %{
          refund_policy_id: policy.id,
          days_before_checkin: 14,
          refund_percentage: Decimal.new(percentage)
        }

        changeset = RefundPolicyRule.changeset(%RefundPolicyRule{}, attrs)

        assert changeset.valid?,
               "Expected refund percentage #{percentage}% to be valid"
      end
    end

    test "rejects negative refund percentage", %{policy: policy} do
      attrs = %{
        refund_policy_id: policy.id,
        days_before_checkin: 14,
        refund_percentage: Decimal.new("-10.0")
      }

      changeset = RefundPolicyRule.changeset(%RefundPolicyRule{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:refund_percentage] != nil
    end

    test "rejects refund percentage over 100", %{policy: policy} do
      attrs = %{
        refund_policy_id: policy.id,
        days_before_checkin: 14,
        refund_percentage: Decimal.new("101.0")
      }

      changeset = RefundPolicyRule.changeset(%RefundPolicyRule{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:refund_percentage] != nil
    end

    test "handles decimal precision", %{policy: policy} do
      attrs = %{
        refund_policy_id: policy.id,
        days_before_checkin: 14,
        refund_percentage: Decimal.new("33.333333")
      }

      changeset = RefundPolicyRule.changeset(%RefundPolicyRule{}, attrs)
      {:ok, rule} = Repo.insert(changeset)

      # Retrieve and verify precision is stored with 2 decimal places (DB column: precision 5, scale 2)
      retrieved = Repo.get(RefundPolicyRule, rule.id)
      assert Decimal.equal?(retrieved.refund_percentage, Decimal.new("33.33"))
    end
  end

  describe "priority field" do
    test "defaults priority to 0", %{policy: policy} do
      attrs = %{
        refund_policy_id: policy.id,
        days_before_checkin: 14,
        refund_percentage: Decimal.new("100.0")
      }

      changeset = RefundPolicyRule.changeset(%RefundPolicyRule{}, attrs)
      {:ok, rule} = Repo.insert(changeset)

      assert rule.priority == 0
    end

    test "accepts custom priority", %{policy: policy} do
      attrs = %{
        refund_policy_id: policy.id,
        days_before_checkin: 14,
        refund_percentage: Decimal.new("100.0"),
        priority: 5
      }

      changeset = RefundPolicyRule.changeset(%RefundPolicyRule{}, attrs)
      {:ok, rule} = Repo.insert(changeset)

      assert rule.priority == 5
    end
  end

  describe "database constraints" do
    test "enforces foreign key constraint on refund_policy_id" do
      invalid_policy_id = Ecto.ULID.generate()

      attrs = %{
        refund_policy_id: invalid_policy_id,
        days_before_checkin: 14,
        refund_percentage: Decimal.new("100.0")
      }

      changeset = RefundPolicyRule.changeset(%RefundPolicyRule{}, attrs)
      {:error, changeset_error} = Repo.insert(changeset)

      assert changeset_error.errors[:refund_policy_id] != nil
    end

    test "can insert and retrieve complete rule", %{policy: policy} do
      attrs = %{
        refund_policy_id: policy.id,
        days_before_checkin: 21,
        refund_percentage: Decimal.new("85.5"),
        description: "85.5% refund for cancellations 21+ days before",
        priority: 2
      }

      changeset = RefundPolicyRule.changeset(%RefundPolicyRule{}, attrs)
      {:ok, rule} = Repo.insert(changeset)

      retrieved = Repo.get(RefundPolicyRule, rule.id)

      assert retrieved.days_before_checkin == 21
      assert Decimal.equal?(retrieved.refund_percentage, Decimal.new("85.5"))

      assert retrieved.description ==
               "85.5% refund for cancellations 21+ days before"

      assert retrieved.priority == 2
      assert retrieved.inserted_at != nil
      assert retrieved.updated_at != nil
    end

    test "can retrieve rule with preloaded policy", %{policy: policy} do
      attrs = %{
        refund_policy_id: policy.id,
        days_before_checkin: 14,
        refund_percentage: Decimal.new("100.0")
      }

      changeset = RefundPolicyRule.changeset(%RefundPolicyRule{}, attrs)
      {:ok, rule} = Repo.insert(changeset)

      retrieved =
        RefundPolicyRule
        |> Repo.get(rule.id)
        |> Repo.preload(:refund_policy)

      assert retrieved.refund_policy.id == policy.id
      assert retrieved.refund_policy.name == "Test Policy"
    end
  end

  describe "typical rule scenarios" do
    test "full refund for early cancellations", %{policy: policy} do
      attrs = %{
        refund_policy_id: policy.id,
        days_before_checkin: 30,
        refund_percentage: Decimal.new("100.0"),
        description: "Full refund for cancellations 30+ days before check-in"
      }

      changeset = RefundPolicyRule.changeset(%RefundPolicyRule{}, attrs)
      {:ok, rule} = Repo.insert(changeset)

      assert rule.days_before_checkin == 30
      assert Decimal.equal?(rule.refund_percentage, Decimal.new("100"))
    end

    test "graduated refund tiers", %{policy: policy} do
      tiers = [
        {30, "100.0", "Full refund 30+ days before"},
        {21, "90.0", "90% refund 21-29 days before"},
        {14, "75.0", "75% refund 14-20 days before"},
        {7, "50.0", "50% refund 7-13 days before"},
        {3, "25.0", "25% refund 3-6 days before"},
        {0, "0.0", "No refund within 3 days"}
      ]

      for {days, percentage, desc} <- tiers do
        attrs = %{
          refund_policy_id: policy.id,
          days_before_checkin: days,
          refund_percentage: Decimal.new(percentage),
          description: desc
        }

        {:ok, _rule} =
          %RefundPolicyRule{}
          |> RefundPolicyRule.changeset(attrs)
          |> Repo.insert()
      end

      # Verify all rules were created
      rules =
        RefundPolicyRule
        |> Ecto.Query.where(refund_policy_id: ^policy.id)
        |> Repo.all()

      assert length(rules) == 6
    end

    test "non-refundable policy", %{policy: policy} do
      attrs = %{
        refund_policy_id: policy.id,
        days_before_checkin: 0,
        refund_percentage: Decimal.new("0.0"),
        description: "All bookings are non-refundable"
      }

      changeset = RefundPolicyRule.changeset(%RefundPolicyRule{}, attrs)
      {:ok, rule} = Repo.insert(changeset)

      assert Decimal.equal?(rule.refund_percentage, Decimal.new("0"))
    end
  end
end
