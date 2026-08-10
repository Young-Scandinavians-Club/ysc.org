defmodule Ysc.PaymentsTest do
  use Ysc.DataCase, async: true

  alias Ysc.Payments
  alias Ysc.Payments.PaymentMethod
  alias Ysc.Repo
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

    test "returns empty list for user with no payment methods" do
      user = user_fixture()
      assert Payments.list_payment_methods(user) == []
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

    test "updates display metadata fields" do
      method = create_payment_method_fixture()

      assert {:ok, updated} =
               Payments.update_payment_method(method, %{
                 last_four: "9999",
                 display_brand: "amex"
               })

      assert updated.last_four == "9999"
      assert updated.display_brand == "amex"
    end

    test "returns error changeset for invalid attributes" do
      method = create_payment_method_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Payments.update_payment_method(method, %{exp_month: 13})
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

    test "deleting a non-default card does not promote another method" do
      user = user_fixture()

      default =
        create_payment_method_fixture(%{user_id: user.id, is_default: true})

      other =
        create_payment_method_fixture(%{user_id: user.id, is_default: false})

      assert {:ok, _} = Payments.delete_payment_method(other)
      assert Payments.get_default_payment_method(user).id == default.id
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

    test "deleting the only payment method leaves no default and empty list" do
      user = user_fixture()

      only =
        create_payment_method_fixture(%{user_id: user.id, is_default: true})

      assert {:ok, _} = Payments.delete_payment_method(only)
      refute Payments.get_default_payment_method(user)
      assert Payments.list_payment_methods(user) == []
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

  describe "insert_payment_method/1 duplicate handling" do
    test "returns changeset error when provider and provider_id already exist" do
      user = user_fixture()
      id = "pm_dup_#{System.unique_integer([:positive])}"

      attrs = %{
        user_id: user.id,
        provider: :stripe,
        provider_id: id,
        provider_customer_id: "cus_dup",
        type: :card,
        provider_type: "card",
        is_default: false
      }

      assert {:ok, _} = Payments.insert_payment_method(attrs)

      case Payments.insert_payment_method(attrs) do
        {:error, :duplicate_payment_method} ->
          :ok

        {:error, %Ecto.Changeset{} = cs} ->
          assert Keyword.has_key?(cs.errors, :provider) or
                   Keyword.has_key?(cs.errors, :provider_id)
      end
    end

    test "returns changeset error when required fields are missing" do
      assert {:error, %Ecto.Changeset{errors: errors}} =
               Payments.insert_payment_method(%{provider: :stripe})

      assert Keyword.has_key?(errors, :provider_id) or
               Keyword.has_key?(errors, :user_id)
    end

    test "returns :duplicate_payment_method when unique constraint maps to provider_id error" do
      user = user_fixture()
      id = "pm_dup_atom_#{System.unique_integer([:positive])}"

      attrs = %{
        user_id: user.id,
        provider: :stripe,
        provider_id: id,
        provider_customer_id: "cus_dup_atom",
        type: :card,
        provider_type: "card",
        is_default: false
      }

      assert {:ok, _} = Payments.insert_payment_method(attrs)

      case Payments.insert_payment_method(attrs) do
        {:error, :duplicate_payment_method} ->
          :ok

        {:error, %Ecto.Changeset{errors: errors}} ->
          assert Keyword.has_key?(errors, :provider_id) or
                   Keyword.has_key?(errors, :provider)
      end
    end
  end

  describe "insert_payment_method_resilient/3 conflict recovery" do
    test "recovers from a unique-constraint conflict without poisoning the enclosing transaction" do
      user = user_fixture()
      pm_id = "pm_resilient_conflict_#{System.unique_integer([:positive])}"

      attrs = %{
        user_id: user.id,
        provider: :stripe,
        provider_id: pm_id,
        provider_customer_id: "cus_resilient_conflict",
        type: :card,
        provider_type: "card",
        is_default: false
      }

      assert {:ok, winner} = Payments.insert_payment_method(attrs)

      # Simulates the webhook handler's enclosing `Repo.transaction/1`: the
      # loser of a race calls insert_payment_method_resilient/3 with attrs
      # that now conflict with `winner`. Before the savepoint fix, the
      # unique-constraint violation aborted this whole transaction at the SQL
      # level, and the subsequent recovery lookup died with
      # `25P02 in_failed_sql_transaction` instead of returning `winner`.
      result =
        Repo.transaction(fn ->
          recovered =
            Payments.insert_payment_method_resilient_for_test(
              user,
              attrs,
              :sync
            )

          # Proves the transaction is still usable afterward.
          reloaded = Repo.get!(PaymentMethod, winner.id)

          {recovered, reloaded}
        end)

      assert {:ok, {{:ok, recovered}, reloaded}} = result
      assert recovered.id == winner.id
      assert reloaded.id == winner.id

      assert Repo.aggregate(
               from(pm in PaymentMethod,
                 where: pm.user_id == ^user.id and pm.provider_id == ^pm_id
               ),
               :count
             ) == 1
    end
  end

  describe "upsert_payment_method_from_stripe/2 and sync_payment_method_from_stripe/2" do
    test "upsert inserts a new payment method and may set default when none exists" do
      user = user_fixture()
      pm_id = "pm_upsert_#{System.unique_integer([:positive])}"

      stripe_pm = %Stripe.PaymentMethod{
        id: pm_id,
        customer: "cus_upsert",
        type: "card",
        card: %Stripe.Card{
          last4: "4242",
          exp_month: 12,
          exp_year: 2030,
          brand: "visa"
        }
      }

      assert {:ok, %Ysc.Payments.PaymentMethod{} = method} =
               Payments.upsert_payment_method_from_stripe(user, stripe_pm)

      assert method.provider_id == pm_id
      assert method.last_four == "4242"
      assert Payments.get_default_payment_method(user) != nil
    end

    test "upsert succeeds when payment method already exists (webhook/LiveView race)" do
      user = user_fixture()
      pm_id = "pm_race_#{System.unique_integer([:positive])}"

      stripe_pm = %Stripe.PaymentMethod{
        id: pm_id,
        customer: "cus_race",
        type: "card",
        card: %Stripe.Card{
          last4: "4242",
          exp_month: 12,
          exp_year: 2030,
          brand: "visa"
        }
      }

      assert {:ok, from_webhook} =
               Payments.sync_payment_method_from_stripe(user, stripe_pm)

      stripe_pm_updated = %{
        stripe_pm
        | card: %{stripe_pm.card | last4: "9999"}
      }

      assert {:ok, from_liveview} =
               Payments.upsert_payment_method_from_stripe(
                 user,
                 stripe_pm_updated
               )

      assert from_liveview.id == from_webhook.id
      assert from_liveview.last_four == "9999"
    end

    test "sync is idempotent when called twice for the same Stripe payment method" do
      user = user_fixture()
      pm_id = "pm_sync_idem_#{System.unique_integer([:positive])}"

      stripe_pm = %Stripe.PaymentMethod{
        id: pm_id,
        customer: "cus_idem",
        type: "card",
        card: %Stripe.Card{
          last4: "4242",
          exp_month: 12,
          exp_year: 2030,
          brand: "visa"
        }
      }

      assert {:ok, first} =
               Payments.sync_payment_method_from_stripe(user, stripe_pm)

      assert {:ok, second} =
               Payments.sync_payment_method_from_stripe(user, stripe_pm)

      assert first.id == second.id
      assert Payments.list_payment_methods(user) |> length() == 1
    end

    test "upsert updates an existing payment method" do
      user = user_fixture()
      pm_id = "pm_update_#{System.unique_integer([:positive])}"

      {:ok, existing} =
        Payments.insert_payment_method(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: pm_id,
          provider_customer_id: "cus_u",
          type: :card,
          provider_type: "card",
          is_default: false
        })

      stripe_pm = %Stripe.PaymentMethod{
        id: pm_id,
        customer: "cus_u",
        type: "card",
        card: %Stripe.Card{
          last4: "9999",
          exp_month: 1,
          exp_year: 2040,
          brand: "visa"
        }
      }

      assert {:ok, updated} =
               Payments.upsert_payment_method_from_stripe(user, stripe_pm)

      assert updated.id == existing.id
      assert updated.last_four == "9999"
    end

    test "upsert does not reassign a payment method row owned by another user" do
      victim = user_fixture()
      attacker = user_fixture()
      pm_id = "pm_idor_#{System.unique_integer([:positive])}"

      {:ok, _} =
        Payments.insert_payment_method(%{
          user_id: victim.id,
          provider: :stripe,
          provider_id: pm_id,
          provider_customer_id: "cus_victim",
          type: :card,
          provider_type: "card",
          is_default: false
        })

      stripe_pm = %Stripe.PaymentMethod{
        id: pm_id,
        customer: "cus_attacker",
        type: "card",
        card: %Stripe.Card{
          last4: "0000",
          exp_month: 6,
          exp_year: 2041,
          brand: "visa"
        }
      }

      assert {:error, :payment_method_owned_by_another_user} =
               Payments.upsert_payment_method_from_stripe(attacker, stripe_pm)

      victim_pm = Payments.get_payment_method_by_provider(:stripe, pm_id)
      assert victim_pm.user_id == victim.id

      refute Enum.any?(
               Payments.list_payment_methods(attacker),
               &(&1.provider_id == pm_id)
             )
    end

    test "sync does not update a payment method row owned by another user" do
      victim = user_fixture()
      attacker = user_fixture()
      pm_id = "pm_sync_idor_#{System.unique_integer([:positive])}"

      {:ok, _} =
        Payments.insert_payment_method(%{
          user_id: victim.id,
          provider: :stripe,
          provider_id: pm_id,
          provider_customer_id: "cus_v2",
          type: :card,
          provider_type: "card",
          is_default: false
        })

      stripe_pm = %Stripe.PaymentMethod{
        id: pm_id,
        customer: "cus_attacker",
        type: "card",
        card: %Stripe.Card{
          last4: "8888",
          exp_month: 7,
          exp_year: 2042,
          brand: "visa"
        }
      }

      assert {:error, :payment_method_owned_by_another_user} =
               Payments.sync_payment_method_from_stripe(attacker, stripe_pm)

      victim_pm = Payments.get_payment_method_by_provider(:stripe, pm_id)
      assert victim_pm.last_four != "8888"
    end

    test "sync_payment_method_from_stripe inserts when missing" do
      user = user_fixture()
      pm_id = "pm_sync_#{System.unique_integer([:positive])}"

      stripe_pm = %Stripe.PaymentMethod{
        id: pm_id,
        customer: "cus_sync",
        type: "card",
        card: %Stripe.Card{
          last4: "1111",
          exp_month: 3,
          exp_year: 2031,
          brand: "mastercard"
        }
      }

      assert {:ok, _} =
               Payments.sync_payment_method_from_stripe(user, stripe_pm)

      assert %Ysc.Payments.PaymentMethod{} =
               Payments.get_payment_method_by_provider(:stripe, pm_id)
    end

    test "sync_payment_method_from_stripe updates existing without forcing default" do
      user = user_fixture()
      pm_id = "pm_sync2_#{System.unique_integer([:positive])}"

      {:ok, _} =
        Payments.insert_payment_method(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: pm_id,
          provider_customer_id: "cus_s2",
          type: :card,
          provider_type: "card",
          is_default: false
        })

      stripe_pm = %Stripe.PaymentMethod{
        id: pm_id,
        customer: "cus_s2",
        type: "card",
        card: %Stripe.Card{
          last4: "2222",
          exp_month: 4,
          exp_year: 2032,
          brand: "visa"
        }
      }

      assert {:ok, m} =
               Payments.sync_payment_method_from_stripe(user, stripe_pm)

      assert m.last_four == "2222"
      refute m.is_default
    end

    test "sync_payment_method_from_stripe returns insert error when user_id is invalid" do
      bad_user = %{user_fixture() | id: Ecto.ULID.generate()}

      stripe_pm = %Stripe.PaymentMethod{
        id: "pm_bad_user_#{System.unique_integer([:positive])}",
        customer: "cus_x",
        type: "card",
        card: %Stripe.Card{
          last4: "4242",
          exp_month: 12,
          exp_year: 2030,
          brand: "visa"
        }
      }

      assert {:error, %Ecto.Changeset{}} =
               Payments.sync_payment_method_from_stripe(bad_user, stripe_pm)
    end

    test "sync_payment_method_from_stripe accepts a plain map (non-struct) payment method" do
      user = user_fixture()
      pm_id = "pm_plain_map_#{System.unique_integer([:positive])}"

      stripe_pm = %{
        id: pm_id,
        customer: "cus_plain",
        type: "card",
        card: %{last4: "4242", exp_month: 11, exp_year: 2031, brand: "visa"},
        us_bank_account: nil
      }

      assert {:ok, _} =
               Payments.sync_payment_method_from_stripe(user, stripe_pm)

      assert %Ysc.Payments.PaymentMethod{} =
               Payments.get_payment_method_by_provider(:stripe, pm_id)
    end

    test "upsert_payment_method_from_stripe returns error when insert fails for invalid user" do
      bad_user = %{user_fixture() | id: Ecto.ULID.generate()}

      stripe_pm = %Stripe.PaymentMethod{
        id: "pm_upsert_bad_#{System.unique_integer([:positive])}",
        customer: "cus_u",
        type: "card",
        card: %Stripe.Card{
          last4: "4242",
          exp_month: 12,
          exp_year: 2030,
          brand: "visa"
        }
      }

      assert {:error, %Ecto.Changeset{}} =
               Payments.upsert_payment_method_from_stripe(bad_user, stripe_pm)
    end
  end

  describe "Stripe type and metadata mapping" do
    test "maps us_bank_account fields from Stripe" do
      user = user_fixture()
      pm_id = "pm_bank_#{System.unique_integer([:positive])}"

      stripe_pm = %Stripe.PaymentMethod{
        id: pm_id,
        customer: "cus_bank",
        type: "us_bank_account",
        card: nil,
        us_bank_account: %{
          last4: "6789",
          routing_number: "110000000",
          bank_name: "Test Bank",
          account_type: "checking"
        }
      }

      assert {:ok, m} =
               Payments.upsert_payment_method_from_stripe(user, stripe_pm)

      assert m.type == :bank_account
      assert m.last_four == "6789"
      assert m.display_brand == "Test Bank"
      assert m.routing_number == "110000000"
      assert m.bank_name == "Test Bank"
    end

    test "upserts card with Stripe Link wallet as type link" do
      user = user_fixture()
      pm_id = "pm_link_wallet_#{System.unique_integer([:positive])}"

      stripe_pm = %{
        id: pm_id,
        customer: "cus_link",
        type: "card",
        card: %{
          last4: "4242",
          exp_month: 12,
          exp_year: 2029,
          brand: "visa",
          display_brand: "visa",
          wallet: %{type: "link", link: %{}}
        },
        us_bank_account: nil
      }

      assert {:ok, _} =
               Payments.sync_payment_method_from_stripe(user, stripe_pm)

      m = Payments.get_payment_method_by_provider(:stripe, pm_id)
      assert m.type == :link
      assert m.last_four == "4242"
    end

    test "upserts Stripe payment method with type link" do
      user = user_fixture()
      pm_id = "pm_link_type_#{System.unique_integer([:positive])}"

      stripe_pm = %Stripe.PaymentMethod{
        id: pm_id,
        customer: "cus_link_type",
        type: "link",
        card: nil
      }

      assert {:ok, %Ysc.Payments.PaymentMethod{} = m} =
               Payments.upsert_payment_method_from_stripe(user, stripe_pm)

      assert m.type == :link
    end

    test "Stripe type mapping covers non-card types (stored type may fail PaymentMethodType enum)" do
      user = user_fixture()

      for stripe_type <- [
            "sepa_debit",
            "paypal",
            "affirm",
            "klarna",
            "cashapp"
          ] do
        pm_id = "pm_type_#{stripe_type}_#{System.unique_integer([:positive])}"

        stripe_pm = %Stripe.PaymentMethod{
          id: pm_id,
          customer: "cus_types",
          type: stripe_type,
          card: nil
        }

        assert {:error, %Ecto.Changeset{}} =
                 Payments.upsert_payment_method_from_stripe(user, stripe_pm)
      end
    end

    test "unknown Stripe provider_type maps through fallback before changeset rejects :other" do
      user = user_fixture()
      pm_id = "pm_other_#{System.unique_integer([:positive])}"

      stripe_pm = %Stripe.PaymentMethod{
        id: pm_id,
        customer: "cus_other",
        type: "crypto",
        card: nil
      }

      assert {:error, %Ecto.Changeset{}} =
               Payments.upsert_payment_method_from_stripe(user, stripe_pm)
    end

    test "get_last_four and get_display_brand fall back to nil when absent" do
      user = user_fixture()
      pm_id = "pm_no_meta_#{System.unique_integer([:positive])}"

      stripe_pm = %Stripe.PaymentMethod{
        id: pm_id,
        customer: "cus_nometa",
        type: "card",
        card: nil
      }

      assert {:ok, m} =
               Payments.upsert_payment_method_from_stripe(user, stripe_pm)

      assert m.last_four == nil
      assert m.display_brand == nil
    end
  end

  describe "upsert_and_set_default_payment_method_from_stripe/2" do
    test "sets the upserted payment method as default" do
      user = user_fixture()

      _ =
        create_payment_method_fixture(%{user_id: user.id, is_default: true})

      pm_id = "pm_default_#{System.unique_integer([:positive])}"

      stripe_pm = %Stripe.PaymentMethod{
        id: pm_id,
        customer: "cus_def",
        type: "card",
        card: %Stripe.Card{
          last4: "3333",
          exp_month: 5,
          exp_year: 2033,
          brand: "visa"
        }
      }

      assert {:ok, _} =
               Payments.upsert_and_set_default_payment_method_from_stripe(
                 user,
                 stripe_pm
               )

      assert Payments.get_default_payment_method(user).provider_id == pm_id
    end

    test "succeeds when payment method already exists from webhook before LiveView upsert" do
      user = user_fixture()
      pm_id = "pm_race_default_#{System.unique_integer([:positive])}"

      stripe_pm = %Stripe.PaymentMethod{
        id: pm_id,
        customer: "cus_race_def",
        type: "card",
        card: %Stripe.Card{
          last4: "4242",
          exp_month: 12,
          exp_year: 2030,
          brand: "visa"
        }
      }

      assert {:ok, _} =
               Payments.sync_payment_method_from_stripe(user, stripe_pm)

      assert {:ok, _} =
               Payments.upsert_and_set_default_payment_method_from_stripe(
                 user,
                 stripe_pm
               )

      assert Payments.get_default_payment_method(user).provider_id == pm_id
    end

    test "returns error when upsert update fails validation" do
      user = user_fixture()
      pm_id = "pm_bad_last4_#{System.unique_integer([:positive])}"

      assert {:ok, _} =
               Payments.insert_payment_method(%{
                 user_id: user.id,
                 provider: :stripe,
                 provider_id: pm_id,
                 provider_customer_id: "cus_bad",
                 type: :card,
                 provider_type: "card",
                 is_default: false
               })

      stripe_pm = %Stripe.PaymentMethod{
        id: pm_id,
        customer: "cus_bad",
        type: "card",
        card: %Stripe.Card{
          last4: "12345",
          exp_month: 12,
          exp_year: 2030,
          brand: "visa"
        }
      }

      assert {:error, %Ecto.Changeset{}} =
               Payments.upsert_and_set_default_payment_method_from_stripe(
                 user,
                 stripe_pm
               )
    end
  end

  describe "set_default_payment_method/2" do
    test "marks one method default and clears previous default" do
      user = user_fixture()

      first =
        create_payment_method_fixture(%{user_id: user.id, is_default: true})

      second =
        create_payment_method_fixture(%{user_id: user.id, is_default: false})

      assert {:ok, _} = Payments.set_default_payment_method(user, second)

      assert Payments.get_default_payment_method(user).id == second.id
      refute Payments.get_payment_method!(first.id).is_default
    end

    test "raises when payment method no longer exists in the database (update_all matches no row)" do
      user = user_fixture()
      pm = create_payment_method_fixture(%{user_id: user.id})

      Repo.delete!(pm)

      assert_raise MatchError, fn ->
        Payments.set_default_payment_method(user, pm)
      end
    end

    test "rejects a payment method owned by a different user" do
      owner = user_fixture()
      caller = user_fixture()

      foreign_pm =
        create_payment_method_fixture(%{user_id: owner.id, is_default: true})

      caller_pm =
        create_payment_method_fixture(%{user_id: caller.id, is_default: true})

      assert {:error, :payment_method_not_owned_by_user} =
               Payments.set_default_payment_method(caller, foreign_pm)

      assert Payments.get_payment_method!(foreign_pm.id).is_default
      assert Payments.get_default_payment_method(caller).id == caller_pm.id
    end
  end

  describe "push_default_payment_method_to_stripe/2" do
    test "updates the Stripe customer's invoice_settings.default_payment_method" do
      user = user_fixture(%{stripe_id: "cus_push_test"})

      pm =
        create_payment_method_fixture(%{
          user_id: user.id,
          provider_id: "pm_push_test"
        })

      expect(Stripe.CustomerMock, :update, fn "cus_push_test", params, _opts ->
        assert params.invoice_settings.default_payment_method == "pm_push_test"
        {:ok, %Stripe.Customer{id: "cus_push_test"}}
      end)

      assert :ok = Payments.push_default_payment_method_to_stripe(user, pm)
    end

    test "is a no-op when the user has no Stripe customer id" do
      user = user_fixture()
      pm = create_payment_method_fixture(%{user_id: user.id})

      # No Stripe.CustomerMock expectation set: this must not call Stripe.
      assert :ok = Payments.push_default_payment_method_to_stripe(user, pm)
    end

    test "logs and returns :ok when the Stripe call fails" do
      user = user_fixture(%{stripe_id: "cus_push_fail"})
      pm = create_payment_method_fixture(%{user_id: user.id})

      expect(Stripe.CustomerMock, :update, fn "cus_push_fail", _params, _opts ->
        {:error,
         %Stripe.Error{
           source: :stripe,
           code: :invalid_request_error,
           message: "boom",
           request_id: nil,
           extra: %{},
           user_message: nil
         }}
      end)

      assert :ok = Payments.push_default_payment_method_to_stripe(user, pm)
    end
  end

  describe "upsert_and_set_default_payment_method_from_stripe/2 pushes to Stripe" do
    test "pushes the new default payment method to the Stripe customer" do
      user = user_fixture(%{stripe_id: "cus_upsert_push"})
      pm_id = "pm_upsert_push_#{System.unique_integer([:positive])}"

      stripe_pm = %Stripe.PaymentMethod{
        id: pm_id,
        customer: "cus_upsert_push",
        type: "card",
        card: %Stripe.Card{
          last4: "4444",
          exp_month: 6,
          exp_year: 2031,
          brand: "visa"
        }
      }

      expect(Stripe.CustomerMock, :update, fn "cus_upsert_push",
                                              params,
                                              _opts ->
        assert params.invoice_settings.default_payment_method == pm_id
        {:ok, %Stripe.Customer{id: "cus_upsert_push"}}
      end)

      assert {:ok, _} =
               Payments.upsert_and_set_default_payment_method_from_stripe(
                 user,
                 stripe_pm
               )
    end
  end

  describe "fix_missing_default_payment_methods/0" do
    test "assigns a default when user has methods but none marked default" do
      user = user_fixture()

      create_payment_method_fixture(%{
        user_id: user.id,
        is_default: false,
        provider_id: "pm_fix1_#{System.unique_integer([:positive])}"
      })

      create_payment_method_fixture(%{
        user_id: user.id,
        is_default: false,
        provider_id: "pm_fix2_#{System.unique_integer([:positive])}"
      })

      refute Payments.get_default_payment_method(user)

      assert {:ok, %{fixed_users: n, total_users: t}} =
               Payments.fix_missing_default_payment_methods()

      assert t >= 1
      assert n >= 1
      assert Payments.get_default_payment_method(user)
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

  describe "sync_payment_methods_with_stripe/1" do
    test "syncs Stripe card payment methods and sets default from customer invoice_settings" do
      user = user_fixture()
      cus_id = "cus_pm_sync_#{System.unique_integer([:positive])}"

      {:ok, user} =
        user
        |> Ecto.Changeset.change(%{stripe_id: cus_id})
        |> Repo.update()

      pm_id = "pm_sync_full_#{System.unique_integer([:positive])}"

      stripe_pm = %Stripe.PaymentMethod{
        id: pm_id,
        customer: cus_id,
        type: "card",
        card: %Stripe.Card{
          last4: "4242",
          exp_month: 12,
          exp_year: 2030,
          brand: "visa"
        }
      }

      stub(Stripe.PaymentMethodMock, :list, fn _params ->
        {:ok,
         %Stripe.List{
           data: [stripe_pm],
           has_more: false,
           object: "list",
           url: "/v1/payment_methods"
         }}
      end)

      stub(Stripe.CustomerMock, :retrieve, fn ^cus_id, _opts ->
        {:ok,
         %Stripe.Customer{
           id: cus_id,
           invoice_settings: %{default_payment_method: pm_id}
         }}
      end)

      assert {:ok, methods} = Payments.sync_payment_methods_with_stripe(user)
      assert Enum.any?(methods, &(&1.provider_id == pm_id))
      assert Payments.get_default_payment_method(user).provider_id == pm_id
    end

    test "returns {:ok, local methods} when Stripe payment method list returns an error" do
      user = user_fixture()
      cus_id = "cus_pm_err_#{System.unique_integer([:positive])}"

      {:ok, user} =
        user
        |> Ecto.Changeset.change(%{stripe_id: cus_id})
        |> Repo.update()

      stub(Stripe.PaymentMethodMock, :list, fn _params ->
        {:error, %Stripe.Error{message: "bad", source: :api, code: :api_error}}
      end)

      stub(Stripe.CustomerMock, :retrieve, fn ^cus_id, _opts ->
        {:ok, %Stripe.Customer{id: cus_id, invoice_settings: nil}}
      end)

      assert {:ok, _} = Payments.sync_payment_methods_with_stripe(user)
    end

    test "does not fail when Stripe default payment method id is missing locally" do
      user = user_fixture()
      cus_id = "cus_orphan_#{System.unique_integer([:positive])}"

      {:ok, user} =
        user
        |> Ecto.Changeset.change(%{stripe_id: cus_id})
        |> Repo.update()

      stub(Stripe.PaymentMethodMock, :list, fn _params ->
        {:ok,
         %Stripe.List{
           data: [],
           has_more: false,
           object: "list",
           url: "/v1/payment_methods"
         }}
      end)

      stub(Stripe.CustomerMock, :retrieve, fn ^cus_id, _opts ->
        {:ok,
         %Stripe.Customer{
           id: cus_id,
           invoice_settings: %{default_payment_method: "pm_not_in_db"}
         }}
      end)

      assert {:ok, _} = Payments.sync_payment_methods_with_stripe(user)
    end

    test "handles Stripe customer retrieve error when resolving default payment method" do
      user = user_fixture()
      cus_id = "cus_cust_err_#{System.unique_integer([:positive])}"

      {:ok, user} =
        user
        |> Ecto.Changeset.change(%{stripe_id: cus_id})
        |> Repo.update()

      stub(Stripe.PaymentMethodMock, :list, fn _params ->
        {:ok,
         %Stripe.List{
           data: [],
           has_more: false,
           object: "list",
           url: "/v1/payment_methods"
         }}
      end)

      stub(Stripe.CustomerMock, :retrieve, fn ^cus_id, _opts ->
        {:error,
         %Stripe.Error{
           message: "missing",
           source: :api,
           code: :resource_missing
         }}
      end)

      assert {:ok, _} = Payments.sync_payment_methods_with_stripe(user)
    end

    test "skips default resolution when customer has no invoice_settings" do
      user = user_fixture()
      cus_id = "cus_no_inv_#{System.unique_integer([:positive])}"

      {:ok, user} =
        user
        |> Ecto.Changeset.change(%{stripe_id: cus_id})
        |> Repo.update()

      stub(Stripe.PaymentMethodMock, :list, fn _params ->
        {:ok,
         %Stripe.List{
           data: [],
           has_more: false,
           object: "list",
           url: "/v1/payment_methods"
         }}
      end)

      stub(Stripe.CustomerMock, :retrieve, fn ^cus_id, _opts ->
        {:ok, %Stripe.Customer{id: cus_id, invoice_settings: nil}}
      end)

      assert {:ok, _} = Payments.sync_payment_methods_with_stripe(user)
    end

    test "skips default resolution when invoice default_payment_method is nil" do
      user = user_fixture()
      cus_id = "cus_nil_defpm_#{System.unique_integer([:positive])}"

      {:ok, user} =
        user
        |> Ecto.Changeset.change(%{stripe_id: cus_id})
        |> Repo.update()

      stub(Stripe.PaymentMethodMock, :list, fn _params ->
        {:ok,
         %Stripe.List{
           data: [],
           has_more: false,
           object: "list",
           url: "/v1/payment_methods"
         }}
      end)

      stub(Stripe.CustomerMock, :retrieve, fn ^cus_id, _opts ->
        {:ok,
         %Stripe.Customer{
           id: cus_id,
           invoice_settings: %{default_payment_method: nil}
         }}
      end)

      assert {:ok, _} = Payments.sync_payment_methods_with_stripe(user)
    end
  end

  describe "get_last_four/1 branches via Stripe upsert" do
    test "prefers dynamic_last4 from card wallet over card.last4" do
      user = user_fixture()
      pm_id = "pm_dynamic_last4_#{System.unique_integer([:positive])}"

      stripe_pm = %{
        id: pm_id,
        customer: "cus_dynamic",
        type: "card",
        card: %{
          last4: "1111",
          exp_month: 12,
          exp_year: 2030,
          brand: "visa",
          wallet: %{type: "apple_pay", dynamic_last4: "9999"}
        },
        us_bank_account: nil
      }

      assert {:ok, m} =
               Payments.sync_payment_method_from_stripe(user, stripe_pm)

      assert m.last_four == "9999"
    end

    test "extracts last four from top-level link payment method" do
      user = user_fixture()
      pm_id = "pm_link_last4_#{System.unique_integer([:positive])}"

      stripe_pm = %{
        id: pm_id,
        customer: "cus_link_top",
        type: "link",
        card: nil,
        us_bank_account: nil,
        link: %{last4: "4321", email: "person@example.com"}
      }

      assert {:ok, m} =
               Payments.sync_payment_method_from_stripe(user, stripe_pm)

      assert m.last_four == "4321"
    end

    test "extracts last four from top-level cashapp payment method" do
      user = user_fixture()
      pm_id = "pm_cashapp_last4_#{System.unique_integer([:positive])}"

      stripe_pm = %{
        id: pm_id,
        customer: "cus_cashapp",
        type: "cashapp",
        card: nil,
        us_bank_account: nil,
        cashapp: %{last4: "6543"}
      }

      assert {:error, %Ecto.Changeset{} = changeset} =
               Payments.sync_payment_method_from_stripe(user, stripe_pm)

      assert Ecto.Changeset.get_field(changeset, :last_four) == "6543"
    end
  end

  describe "get_display_brand/1 branches via Stripe upsert" do
    test "maps wallet types apple_pay, google_pay, and samsung_pay to display names" do
      user = user_fixture()

      for {wallet_type, expected_brand} <- [
            {"apple_pay", "Apple Pay"},
            {"google_pay", "Google Pay"},
            {"samsung_pay", "Samsung Pay"}
          ] do
        pm_id = "pm_wallet_#{wallet_type}_#{System.unique_integer([:positive])}"

        stripe_pm = %{
          id: pm_id,
          customer: "cus_wallet",
          type: "card",
          card: %{
            last4: "1234",
            exp_month: 12,
            exp_year: 2030,
            brand: "visa",
            wallet: %{type: wallet_type}
          },
          us_bank_account: nil
        }

        assert {:ok, m} =
                 Payments.sync_payment_method_from_stripe(user, stripe_pm)

        assert m.display_brand == expected_brand
      end
    end

    test "falls back to display_brand/brand for unrecognized wallet type" do
      user = user_fixture()
      pm_id = "pm_unknown_wallet_#{System.unique_integer([:positive])}"

      stripe_pm = %{
        id: pm_id,
        customer: "cus_unknown_wallet",
        type: "card",
        card: %{
          last4: "1234",
          exp_month: 12,
          exp_year: 2030,
          brand: "mastercard",
          display_brand: "mastercard",
          wallet: %{type: "some_future_wallet"}
        },
        us_bank_account: nil
      }

      assert {:ok, m} =
               Payments.sync_payment_method_from_stripe(user, stripe_pm)

      assert m.display_brand == "mastercard"
    end

    test "uses 'Link' brand for card with brand link and no wallet" do
      user = user_fixture()
      pm_id = "pm_card_brand_link_#{System.unique_integer([:positive])}"

      stripe_pm = %{
        id: pm_id,
        customer: "cus_card_link",
        type: "card",
        card: %{last4: "1234", exp_month: 12, exp_year: 2030, brand: "link"},
        us_bank_account: nil
      }

      assert {:ok, m} =
               Payments.sync_payment_method_from_stripe(user, stripe_pm)

      assert m.display_brand == "Link"
    end

    test "uses card display_brand when present and not link" do
      user = user_fixture()
      pm_id = "pm_card_display_brand_#{System.unique_integer([:positive])}"

      stripe_pm = %{
        id: pm_id,
        customer: "cus_card_display",
        type: "card",
        card: %{
          last4: "1234",
          exp_month: 12,
          exp_year: 2030,
          brand: "visa",
          display_brand: "visa debit"
        },
        us_bank_account: nil
      }

      assert {:ok, m} =
               Payments.sync_payment_method_from_stripe(user, stripe_pm)

      assert m.display_brand == "visa debit"
    end

    test "derives display brand from top-level link map email/country" do
      user = user_fixture()
      pm_id = "pm_link_map_#{System.unique_integer([:positive])}"

      stripe_pm = %{
        id: pm_id,
        customer: "cus_link_display",
        type: "link",
        card: nil,
        us_bank_account: nil,
        link: %{country: "US"}
      }

      assert {:ok, m} =
               Payments.sync_payment_method_from_stripe(user, stripe_pm)

      assert m.display_brand == "US"
    end

    test "maps top-level cashapp, paypal, klarna, affirm to expected display brands" do
      user = user_fixture()

      for {type, key, expected_brand} <- [
            {"cashapp", :cashapp, "Cash App"},
            {"paypal", :paypal, "PayPal"},
            {"klarna", :klarna, "Klarna"},
            {"affirm", :affirm, "Affirm"}
          ] do
        pm_id = "pm_#{type}_brand_#{System.unique_integer([:positive])}"

        stripe_pm = %{
          id: pm_id,
          customer: "cus_#{type}",
          type: type,
          card: nil,
          us_bank_account: nil
        }

        stripe_pm = Map.put(stripe_pm, key, %{some: "value"})

        assert {:error, %Ecto.Changeset{} = changeset} =
                 Payments.sync_payment_method_from_stripe(user, stripe_pm)

        assert Ecto.Changeset.get_field(changeset, :display_brand) ==
                 expected_brand
      end
    end
  end

  describe "stripe_payment_method_to_map/1 nested list conversion" do
    test "converts list-valued fields when payload is a plain map" do
      user = user_fixture()
      pm_id = "pm_list_field_#{System.unique_integer([:positive])}"

      stripe_pm = %{
        id: pm_id,
        customer: "cus_list_field",
        type: "card",
        card: %{last4: "1234", exp_month: 12, exp_year: 2030, brand: "visa"},
        us_bank_account: nil,
        some_list_field: ["a", "b", %{nested: "c"}]
      }

      assert {:ok, m} =
               Payments.sync_payment_method_from_stripe(user, stripe_pm)

      assert m.payload[:some_list_field] == ["a", "b", %{nested: "c"}]
    end
  end

  describe "ci_query_explain_query/0" do
    test "returns a valid Ecto query usable for query-explain tooling" do
      assert %Ecto.Query{} = Payments.ci_query_explain_query()
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
