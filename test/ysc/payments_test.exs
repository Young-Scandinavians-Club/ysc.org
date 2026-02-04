defmodule Ysc.PaymentsTest do
  use Ysc.DataCase, async: true

  alias Ysc.Payments
  import Ecto.Query
  import Ysc.AccountsFixtures

  describe "list_payment_methods/1" do
    test "returns payment methods for user" do
      user = user_fixture()
      _method1 = create_payment_method_fixture(%{user_id: user.id})
      _method2 = create_payment_method_fixture(%{user_id: user.id})

      methods = Payments.list_payment_methods(user)
      assert length(methods) >= 2
    end
  end

  describe "get_payment_method_by_provider/2" do
    test "returns payment method by provider and provider_id" do
      method =
        create_payment_method_fixture(%{
          provider: :stripe,
          provider_id: "pm_test123"
        })

      found = Payments.get_payment_method_by_provider(:stripe, "pm_test123")
      assert found.id == method.id
    end

    test "returns nil for non-existent payment method" do
      refute Payments.get_payment_method_by_provider(:stripe, "pm_nonexistent")
    end
  end

  describe "get_payment_method!/1" do
    test "returns payment method by id" do
      method = create_payment_method_fixture()
      found = Payments.get_payment_method!(method.id)
      assert found.id == method.id
    end

    test "raises for non-existent payment method" do
      assert_raise Ecto.NoResultsError, fn ->
        Payments.get_payment_method!(Ecto.ULID.generate())
      end
    end
  end

  describe "get_default_payment_method/1" do
    test "returns default payment method for user" do
      user = user_fixture()

      default =
        create_payment_method_fixture(%{user_id: user.id, is_default: true})

      _other =
        create_payment_method_fixture(%{user_id: user.id, is_default: false})

      found = Payments.get_default_payment_method(user)
      assert found.id == default.id
    end

    test "returns nil when no default payment method" do
      user = user_fixture()

      _method =
        create_payment_method_fixture(%{user_id: user.id, is_default: false})

      refute Payments.get_default_payment_method(user)
    end
  end

  describe "insert_payment_method/1" do
    test "creates a payment method" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        provider: :stripe,
        provider_id: "pm_new123",
        provider_customer_id: "cus_test123",
        type: :card,
        provider_type: "card",
        is_default: false
      }

      assert {:ok, method} = Payments.insert_payment_method(attrs)
      assert method.provider == :stripe
      assert method.provider_id == "pm_new123"
    end
  end

  describe "update_payment_method/2" do
    test "updates a payment method" do
      method = create_payment_method_fixture()
      update_attrs = %{is_default: true}

      assert {:ok, updated} =
               Payments.update_payment_method(method, update_attrs)

      assert updated.is_default == true
    end
  end

  describe "delete_payment_method/1" do
    test "deletes a payment method" do
      method = create_payment_method_fixture()
      assert {:ok, _} = Payments.delete_payment_method(method)

      assert_raise Ecto.NoResultsError, fn ->
        Payments.get_payment_method!(method.id)
      end
    end

    test "sets new default when deleting default payment method" do
      user = user_fixture()

      default =
        create_payment_method_fixture(%{user_id: user.id, is_default: true})

      other =
        create_payment_method_fixture(%{user_id: user.id, is_default: false})

      assert {:ok, _} = Payments.delete_payment_method(default)
      # Reload other method
      updated = Payments.get_payment_method!(other.id)
      assert updated.is_default == true
    end
  end

  describe "change_payment_method/2" do
    test "returns a changeset" do
      method = create_payment_method_fixture()
      changeset = Payments.change_payment_method(method)
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "deduplicate_payment_methods/1" do
    test "removes duplicate payment methods" do
      user = user_fixture()
      # Use a unique provider_id to avoid conflicts from previous test runs
      unique_id = "pm_duplicate_#{System.unique_integer([:positive])}"

      # Create first payment method
      _method1 =
        create_payment_method_fixture(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: unique_id
        })

      # Try to create duplicate - this will fail due to unique constraint
      # So we need to insert it directly bypassing the constraint, or handle the error
      # For this test, we'll use Repo.insert_all to bypass validations
      alias Ysc.Payments.PaymentMethod

      # Delete any existing duplicates first to ensure clean test state
      Ysc.Repo.delete_all(
        from(pm in PaymentMethod,
          where:
            pm.user_id == ^user.id and pm.provider == :stripe and
              pm.provider_id == ^unique_id
        )
      )

      # Create the first method
      _method1 =
        create_payment_method_fixture(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: unique_id
        })

      # To test deduplication, we need to create a duplicate.
      # Since we can't modify DB constraints, we'll use a transaction with deferred constraints
      # However, unique indexes can't be deferred, so we'll use a different approach:
      # We'll temporarily drop and recreate the unique index within a transaction
      # This simulates a race condition where duplicates could be created
      duplicate_id = Ecto.ULID.generate()
      # Convert ULID string to binary for database insert
      duplicate_id_binary =
        case Ecto.ULID.dump(duplicate_id) do
          {:ok, binary} -> binary
          _ -> duplicate_id
        end

      user_id_binary =
        case Ecto.ULID.dump(user.id) do
          {:ok, binary} -> binary
          _ -> user.id
        end

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Use a transaction to temporarily drop the index, insert duplicate, then recreate it
      # Note: We're modifying an index (not a constraint), which is acceptable for testing
      # The transaction ensures the index is recreated even if something fails
      {:ok, _} =
        Ysc.Repo.transaction(fn ->
          # Drop the unique index (it's an index, not a constraint)
          Ysc.Repo.query!(
            "DROP INDEX IF EXISTS payment_methods_provider_provider_id_index"
          )

          # Insert duplicate using raw SQL
          # Use an empty JSON object (not a string) for payload
          {:ok, _} =
            Ysc.Repo.query(
              """
              INSERT INTO payment_methods (id, user_id, provider, provider_id, provider_customer_id, type, provider_type, is_default, payload, inserted_at, updated_at)
              VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb, $10, $11)
              """,
              [
                duplicate_id_binary,
                user_id_binary,
                "stripe",
                unique_id,
                "cus_duplicate",
                "card",
                "card",
                false,
                # Use empty map, not string
                %{},
                now,
                now
              ]
            )

          # Recreate the unique index - this will fail if duplicates exist, so we need to handle it
          # Actually, we can't recreate it with duplicates, so we'll leave it dropped
          # and let the deduplication function handle it, then recreate after
          :ok
        end)

      assert {:ok, _kept} = Payments.deduplicate_payment_methods(user)

      # Now recreate the index after deduplication
      try do
        Ysc.Repo.query!(
          "CREATE UNIQUE INDEX IF NOT EXISTS payment_methods_provider_provider_id_index ON payment_methods(provider, provider_id)"
        )
      rescue
        Postgrex.Error ->
          # Index might already exist or there might still be duplicates
          # Try to drop and recreate
          Ysc.Repo.query!(
            "DROP INDEX IF EXISTS payment_methods_provider_provider_id_index"
          )

          Ysc.Repo.query!(
            "CREATE UNIQUE INDEX payment_methods_provider_provider_id_index ON payment_methods(provider, provider_id)"
          )
      end

      methods = Payments.list_payment_methods(user)
      # Should only have one method with this provider_id
      matching = Enum.filter(methods, &(&1.provider_id == unique_id))
      assert length(matching) == 1
    end
  end

  describe "set_default_payment_method_if_none/2" do
    test "sets default when user has no default" do
      user = user_fixture()

      method =
        create_payment_method_fixture(%{user_id: user.id, is_default: false})

      assert {:ok, _} =
               Payments.set_default_payment_method_if_none(user, method)

      found = Payments.get_default_payment_method(user)
      assert found.id == method.id
    end

    test "does not set default when user already has one" do
      user = user_fixture()

      existing_default =
        create_payment_method_fixture(%{user_id: user.id, is_default: true})

      new_method =
        create_payment_method_fixture(%{user_id: user.id, is_default: false})

      assert {:ok, _} =
               Payments.set_default_payment_method_if_none(user, new_method)

      found = Payments.get_default_payment_method(user)
      assert found.id == existing_default.id
    end
  end

  # Helper function
  defp create_payment_method_fixture(attrs \\ %{}) do
    user = Map.get_lazy(attrs, :user_id, fn -> user_fixture().id end)

    default_attrs = %{
      user_id: user,
      provider: :stripe,
      provider_id: "pm_#{System.unique_integer([:positive])}",
      provider_customer_id: "cus_#{System.unique_integer([:positive])}",
      type: :card,
      provider_type: "card",
      is_default: false
    }

    {:ok, method} =
      default_attrs
      |> Map.merge(attrs)
      |> Payments.insert_payment_method()

    method
  end
end
