defmodule Ysc.Payments.PaymentMethodTest do
  @moduledoc """
  Tests for PaymentMethod schema.

  These tests verify:
  - Changeset validations for all fields
  - Provider and type enum handling
  - Card-specific field validations (exp_month, exp_year)
  - Bank account field validations
  - Default payment method constraint
  - Unique constraints
  - User association
  """
  use Ysc.DataCase, async: true

  alias Ysc.Payments.PaymentMethod
  alias Ysc.Repo

  import Ysc.AccountsFixtures

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "changeset/2 - required fields" do
    test "creates valid changeset with all required fields for card", %{
      user: user
    } do
      attrs = %{
        provider: :stripe,
        provider_id: "pm_test_123",
        provider_customer_id: "cus_test_123",
        type: :card,
        provider_type: "card",
        user_id: user.id
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)

      assert changeset.valid?
      assert changeset.changes.provider == :stripe
      assert changeset.changes.type == :card
    end

    test "requires provider" do
      attrs = %{
        provider_id: "pm_test_123",
        provider_customer_id: "cus_test_123",
        type: :card,
        provider_type: "card"
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:provider] != nil
    end

    test "requires provider_id" do
      attrs = %{
        provider: :stripe,
        provider_customer_id: "cus_test_123",
        type: :card,
        provider_type: "card"
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:provider_id] != nil
    end

    test "requires provider_customer_id" do
      attrs = %{
        provider: :stripe,
        provider_id: "pm_test_123",
        type: :card,
        provider_type: "card"
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:provider_customer_id] != nil
    end

    test "requires type" do
      attrs = %{
        provider: :stripe,
        provider_id: "pm_test_123",
        provider_customer_id: "cus_test_123",
        provider_type: "card"
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:type] != nil
    end

    test "requires provider_type" do
      attrs = %{
        provider: :stripe,
        provider_id: "pm_test_123",
        provider_customer_id: "cus_test_123",
        type: :card
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:provider_type] != nil
    end

    test "requires user_id" do
      attrs = %{
        provider: :stripe,
        provider_id: "pm_test_123",
        provider_customer_id: "cus_test_123",
        type: :card,
        provider_type: "card"
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:user_id] != nil
    end
  end

  describe "changeset/2 - card fields" do
    test "accepts valid card with expiration" do
      user = user_fixture()

      attrs = %{
        provider: :stripe,
        provider_id: "pm_card_123",
        provider_customer_id: "cus_123",
        type: :card,
        provider_type: "card",
        user_id: user.id,
        last_four: "4242",
        display_brand: "Visa",
        exp_month: 12,
        exp_year: 2030
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)

      assert changeset.valid?
      assert changeset.changes.last_four == "4242"
      assert changeset.changes.display_brand == "Visa"
      assert changeset.changes.exp_month == 12
      assert changeset.changes.exp_year == 2030
    end

    test "validates last_four maximum length" do
      user = user_fixture()

      attrs = %{
        provider: :stripe,
        provider_id: "pm_card_123",
        provider_customer_id: "cus_123",
        type: :card,
        provider_type: "card",
        user_id: user.id,
        last_four: "12345"
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:last_four] != nil
    end

    test "accepts last_four with exactly 4 characters" do
      user = user_fixture()

      attrs = %{
        provider: :stripe,
        provider_id: "pm_card_123",
        provider_customer_id: "cus_123",
        type: :card,
        provider_type: "card",
        user_id: user.id,
        last_four: "1234"
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)

      assert changeset.valid?
    end

    test "validates exp_month range (1-12)" do
      user = user_fixture()

      # Test invalid month (0)
      attrs_zero = %{
        provider: :stripe,
        provider_id: "pm_card_123",
        provider_customer_id: "cus_123",
        type: :card,
        provider_type: "card",
        user_id: user.id,
        exp_month: 0,
        exp_year: 2030
      }

      changeset_zero = PaymentMethod.changeset(%PaymentMethod{}, attrs_zero)
      refute changeset_zero.valid?
      assert changeset_zero.errors[:exp_month] != nil

      # Test invalid month (13)
      attrs_high = Map.put(attrs_zero, :exp_month, 13)
      changeset_high = PaymentMethod.changeset(%PaymentMethod{}, attrs_high)
      refute changeset_high.valid?
      assert changeset_high.errors[:exp_month] != nil
    end

    test "accepts valid exp_month values (1-12)" do
      user = user_fixture()

      for month <- 1..12 do
        attrs = %{
          provider: :stripe,
          provider_id: "pm_card_#{month}",
          provider_customer_id: "cus_123",
          type: :card,
          provider_type: "card",
          user_id: user.id,
          exp_month: month,
          exp_year: 2030
        }

        changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)
        assert changeset.valid?, "Expected exp_month #{month} to be valid"
      end
    end

    test "validates exp_year must be greater than 2000" do
      user = user_fixture()

      attrs = %{
        provider: :stripe,
        provider_id: "pm_card_123",
        provider_customer_id: "cus_123",
        type: :card,
        provider_type: "card",
        user_id: user.id,
        exp_month: 12,
        exp_year: 1999
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:exp_year] != nil
    end

    test "accepts exp_year values greater than 2000" do
      user = user_fixture()

      attrs = %{
        provider: :stripe,
        provider_id: "pm_card_123",
        provider_customer_id: "cus_123",
        type: :card,
        provider_type: "card",
        user_id: user.id,
        exp_month: 12,
        exp_year: 2025
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)

      assert changeset.valid?
    end

    test "validates display_brand maximum length" do
      user = user_fixture()

      long_brand = String.duplicate("a", 256)

      attrs = %{
        provider: :stripe,
        provider_id: "pm_card_123",
        provider_customer_id: "cus_123",
        type: :card,
        provider_type: "card",
        user_id: user.id,
        display_brand: long_brand
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:display_brand] != nil
    end
  end

  describe "changeset/2 - bank account fields" do
    test "accepts valid bank account" do
      user = user_fixture()

      attrs = %{
        provider: :stripe,
        provider_id: "ba_test_123",
        provider_customer_id: "cus_123",
        type: :bank_account,
        provider_type: "bank_account",
        user_id: user.id,
        last_four: "6789",
        account_type: "checking",
        routing_number: "110000000",
        bank_name: "Test Bank"
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)

      assert changeset.valid?
      assert changeset.changes.account_type == "checking"
      assert changeset.changes.routing_number == "110000000"
      assert changeset.changes.bank_name == "Test Bank"
    end

    test "validates account_type maximum length" do
      user = user_fixture()

      long_type = String.duplicate("a", 256)

      attrs = %{
        provider: :stripe,
        provider_id: "ba_test_123",
        provider_customer_id: "cus_123",
        type: :bank_account,
        provider_type: "bank_account",
        user_id: user.id,
        account_type: long_type
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:account_type] != nil
    end

    test "validates routing_number maximum length" do
      user = user_fixture()

      long_routing = String.duplicate("1", 256)

      attrs = %{
        provider: :stripe,
        provider_id: "ba_test_123",
        provider_customer_id: "cus_123",
        type: :bank_account,
        provider_type: "bank_account",
        user_id: user.id,
        routing_number: long_routing
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:routing_number] != nil
    end

    test "validates bank_name maximum length" do
      user = user_fixture()

      long_name = String.duplicate("a", 256)

      attrs = %{
        provider: :stripe,
        provider_id: "ba_test_123",
        provider_customer_id: "cus_123",
        type: :bank_account,
        provider_type: "bank_account",
        user_id: user.id,
        bank_name: long_name
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:bank_name] != nil
    end
  end

  describe "changeset/2 - provider validation" do
    test "accepts stripe provider" do
      user = user_fixture()

      attrs = %{
        provider: :stripe,
        provider_id: "pm_test_123",
        provider_customer_id: "cus_123",
        type: :card,
        provider_type: "card",
        user_id: user.id
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)

      assert changeset.valid?
      assert changeset.changes.provider == :stripe
    end

    test "rejects invalid provider" do
      attrs = %{
        provider: :invalid_provider,
        provider_id: "pm_test_123",
        provider_customer_id: "cus_123",
        type: :card,
        provider_type: "card"
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)
      refute changeset.valid?
    end

    test "validates provider_id maximum length" do
      user = user_fixture()

      long_id = String.duplicate("a", 256)

      attrs = %{
        provider: :stripe,
        provider_id: long_id,
        provider_customer_id: "cus_123",
        type: :card,
        provider_type: "card",
        user_id: user.id
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:provider_id] != nil
    end

    test "validates provider_customer_id maximum length" do
      user = user_fixture()

      long_id = String.duplicate("a", 256)

      attrs = %{
        provider: :stripe,
        provider_id: "pm_test_123",
        provider_customer_id: long_id,
        type: :card,
        provider_type: "card",
        user_id: user.id
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:provider_customer_id] != nil
    end
  end

  describe "changeset/2 - type validation" do
    test "accepts card type" do
      user = user_fixture()

      attrs = %{
        provider: :stripe,
        provider_id: "pm_test_123",
        provider_customer_id: "cus_123",
        type: :card,
        provider_type: "card",
        user_id: user.id
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)

      assert changeset.valid?
      assert changeset.changes.type == :card
    end

    test "accepts bank_account type" do
      user = user_fixture()

      attrs = %{
        provider: :stripe,
        provider_id: "ba_test_123",
        provider_customer_id: "cus_123",
        type: :bank_account,
        provider_type: "bank_account",
        user_id: user.id
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)

      assert changeset.valid?
      assert changeset.changes.type == :bank_account
    end

    test "rejects invalid type" do
      attrs = %{
        provider: :stripe,
        provider_id: "pm_test_123",
        provider_customer_id: "cus_123",
        type: :invalid_type,
        provider_type: "card"
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)
      refute changeset.valid?
    end

    test "validates provider_type maximum length" do
      user = user_fixture()

      long_type = String.duplicate("a", 256)

      attrs = %{
        provider: :stripe,
        provider_id: "pm_test_123",
        provider_customer_id: "cus_123",
        type: :card,
        provider_type: long_type,
        user_id: user.id
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:provider_type] != nil
    end
  end

  describe "changeset/2 - default payment method" do
    test "defaults is_default to false" do
      user = user_fixture()

      attrs = %{
        provider: :stripe,
        provider_id: "pm_test_123",
        provider_customer_id: "cus_123",
        type: :card,
        provider_type: "card",
        user_id: user.id
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)
      {:ok, payment_method} = Repo.insert(changeset)

      assert payment_method.is_default == false
    end

    test "can set is_default to true" do
      user = user_fixture()

      attrs = %{
        provider: :stripe,
        provider_id: "pm_test_123",
        provider_customer_id: "cus_123",
        type: :card,
        provider_type: "card",
        user_id: user.id,
        is_default: true
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)
      {:ok, payment_method} = Repo.insert(changeset)

      assert payment_method.is_default == true
    end

    test "allows multiple non-default payment methods per user" do
      user = user_fixture()

      attrs1 = %{
        provider: :stripe,
        provider_id: "pm_test_1",
        provider_customer_id: "cus_123",
        type: :card,
        provider_type: "card",
        user_id: user.id,
        is_default: false
      }

      attrs2 = %{
        provider: :stripe,
        provider_id: "pm_test_2",
        provider_customer_id: "cus_123",
        type: :card,
        provider_type: "card",
        user_id: user.id,
        is_default: false
      }

      changeset1 = PaymentMethod.changeset(%PaymentMethod{}, attrs1)
      changeset2 = PaymentMethod.changeset(%PaymentMethod{}, attrs2)

      {:ok, _pm1} = Repo.insert(changeset1)
      {:ok, _pm2} = Repo.insert(changeset2)

      # Both should coexist
      payment_methods =
        PaymentMethod
        |> Ecto.Query.where(user_id: ^user.id)
        |> Repo.all()

      assert length(payment_methods) == 2
    end
  end

  describe "changeset/2 - payload field" do
    test "accepts payload map" do
      user = user_fixture()

      attrs = %{
        provider: :stripe,
        provider_id: "pm_test_123",
        provider_customer_id: "cus_123",
        type: :card,
        provider_type: "card",
        user_id: user.id,
        payload: %{"stripe_data" => "test_value"}
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)

      assert changeset.valid?
      assert changeset.changes.payload == %{"stripe_data" => "test_value"}
    end

    test "defaults payload to empty map" do
      user = user_fixture()

      attrs = %{
        provider: :stripe,
        provider_id: "pm_test_123",
        provider_customer_id: "cus_123",
        type: :card,
        provider_type: "card",
        user_id: user.id
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)
      {:ok, payment_method} = Repo.insert(changeset)

      assert payment_method.payload == %{}
    end
  end

  describe "database constraints" do
    test "enforces unique constraint on provider and provider_id", %{user: user} do
      attrs = %{
        provider: :stripe,
        provider_id: "pm_unique_test",
        provider_customer_id: "cus_123",
        type: :card,
        provider_type: "card",
        user_id: user.id
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)
      {:ok, _pm1} = Repo.insert(changeset)

      # Try to insert another payment method with same provider and provider_id
      changeset2 = PaymentMethod.changeset(%PaymentMethod{}, attrs)
      {:error, changeset_error} = Repo.insert(changeset2)

      # Check for constraint error (might be on provider or provider_id)
      assert changeset_error.errors[:provider] != nil or
               changeset_error.errors[:provider_id] != nil
    end

    test "enforces foreign key constraint on user_id" do
      invalid_user_id = Ecto.ULID.generate()

      attrs = %{
        provider: :stripe,
        provider_id: "pm_test_123",
        provider_customer_id: "cus_123",
        type: :card,
        provider_type: "card",
        user_id: invalid_user_id
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)
      {:error, changeset_error} = Repo.insert(changeset)

      assert changeset_error.errors[:user_id] != nil
    end

    test "can insert and retrieve complete payment method", %{user: user} do
      attrs = %{
        provider: :stripe,
        provider_id: "pm_complete_test",
        provider_customer_id: "cus_complete",
        type: :card,
        provider_type: "card",
        user_id: user.id,
        last_four: "4242",
        display_brand: "Visa",
        exp_month: 12,
        exp_year: 2030,
        is_default: true,
        payload: %{"test" => "data"}
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)
      {:ok, payment_method} = Repo.insert(changeset)

      retrieved = Repo.get(PaymentMethod, payment_method.id)

      assert retrieved.provider == :stripe
      assert retrieved.provider_id == "pm_complete_test"
      assert retrieved.provider_customer_id == "cus_complete"
      assert retrieved.type == :card
      assert retrieved.provider_type == "card"
      assert retrieved.user_id == user.id
      assert retrieved.last_four == "4242"
      assert retrieved.display_brand == "Visa"
      assert retrieved.exp_month == 12
      assert retrieved.exp_year == 2030
      assert retrieved.is_default == true
      assert retrieved.payload == %{"test" => "data"}
      assert retrieved.inserted_at != nil
      assert retrieved.updated_at != nil
    end

    test "can retrieve payment method with preloaded user", %{user: user} do
      attrs = %{
        provider: :stripe,
        provider_id: "pm_preload_test",
        provider_customer_id: "cus_123",
        type: :card,
        provider_type: "card",
        user_id: user.id
      }

      changeset = PaymentMethod.changeset(%PaymentMethod{}, attrs)
      {:ok, payment_method} = Repo.insert(changeset)

      retrieved =
        PaymentMethod
        |> Repo.get(payment_method.id)
        |> Repo.preload(:user)

      assert retrieved.user.id == user.id
      assert retrieved.user.email == user.email
    end
  end
end
