defmodule Ysc.AccountsTest do
  use Ysc.DataCase, async: false

  alias Ysc.Accounts
  alias Ysc.Repo

  import Ysc.AccountsFixtures
  alias Ysc.Accounts.{User, UserPasskey, UserToken, UserProfileCache}
  alias Ysc.Payments.PaymentMethod
  alias Ysc.Subscriptions
  alias Ysc.Newsletter

  defp user_with_lifetime_membership(attrs) do
    user_fixture(attrs)
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at:
        DateTime.truncate(DateTime.utc_now(), :second)
    )
    |> Repo.update!()
  end

  defp user_with_family_subscription(attrs) do
    user = user_fixture(attrs)

    membership_plans = Application.get_env(:ysc, :membership_plans, [])
    family_plan = Enum.find(membership_plans, &(&1.id == :family))

    if family_plan do
      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_test_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Family Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 365, :day)
        })

      {:ok, _item} =
        Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_price_id: family_plan.stripe_price_id,
          stripe_product_id: "prod_test_#{System.unique_integer()}",
          stripe_id: "si_test_#{System.unique_integer()}",
          quantity: 1
        })

      Accounts.get_user!(user.id, [:subscriptions])
    else
      user
    end
  end

  defp user_with_single_subscription(attrs) do
    user = user_fixture(attrs)

    membership_plans = Application.get_env(:ysc, :membership_plans, [])
    single_plan = Enum.find(membership_plans, &(&1.id == :single))

    if single_plan do
      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_test_single_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Single Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 365, :day)
        })

      {:ok, _item} =
        Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_price_id: single_plan.stripe_price_id,
          stripe_product_id: "prod_test_single_#{System.unique_integer()}",
          stripe_id: "si_test_single_#{System.unique_integer()}",
          quantity: 1
        })

      Accounts.get_user!(user.id, [:subscriptions])
    else
      user
    end
  end

  defp primary_with_active_subscription_no_items(attrs) do
    user = user_fixture(attrs)

    {:ok, _subscription} =
      Subscriptions.create_subscription(%{
        user_id: user.id,
        stripe_id: "sub_no_items_#{System.unique_integer()}",
        stripe_status: "active",
        name: "Membership",
        current_period_end: DateTime.add(DateTime.utc_now(), 365, :day)
      })

    Accounts.get_user!(user.id, [:subscriptions])
  end

  defp user_with_cancelled_subscription(attrs) do
    user = user_fixture(attrs)

    {:ok, _subscription} =
      Subscriptions.create_subscription(%{
        user_id: user.id,
        stripe_id: "sub_cancelled_#{System.unique_integer()}",
        stripe_status: "cancelled",
        name: "Cancelled Membership",
        current_period_end: DateTime.add(DateTime.utc_now(), 365, :day)
      })

    user
  end

  defp user_with_expired_subscription(attrs) do
    user = user_fixture(attrs)

    {:ok, _subscription} =
      Subscriptions.create_subscription(%{
        user_id: user.id,
        stripe_id: "sub_expired_#{System.unique_integer()}",
        stripe_status: "active",
        name: "Expired Membership",
        current_period_end: DateTime.add(DateTime.utc_now(), -1, :day)
      })

    user
  end

  defp user_with_past_ends_at_subscription(attrs) do
    user = user_fixture(attrs)

    {:ok, _subscription} =
      Subscriptions.create_subscription(%{
        user_id: user.id,
        stripe_id: "sub_ended_#{System.unique_integer()}",
        stripe_status: "active",
        name: "Ended Membership",
        current_period_end: DateTime.add(DateTime.utc_now(), 30, :day),
        ends_at: DateTime.add(DateTime.utc_now(), -1, :day)
      })

    user
  end

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture(%{phone_number: "+14159098268"})
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end

    test "normalizes Gmail addresses - finds user by email without dots" do
      %{id: id} = user_fixture(%{email: "johndoe@gmail.com"})
      assert %User{id: ^id} = Accounts.get_user_by_email("john.doe@gmail.com")

      assert %User{id: ^id} =
               Accounts.get_user_by_email("j.o.h.n.d.o.e@gmail.com")
    end

    test "normalizes Gmail addresses - finds user by email without plus-addressing" do
      %{id: id} = user_fixture(%{email: "testuser@gmail.com"})

      assert %User{id: ^id} =
               Accounts.get_user_by_email("testuser+tag@gmail.com")

      assert %User{id: ^id} =
               Accounts.get_user_by_email("testuser+work@gmail.com")
    end

    test "normalizes Gmail addresses - finds user with dots and plus-addressing variations" do
      %{id: id} = user_fixture(%{email: "johndoe@gmail.com"})

      assert %User{id: ^id} =
               Accounts.get_user_by_email("john.doe+test@gmail.com")

      assert %User{id: ^id} =
               Accounts.get_user_by_email("j.o.h.n.doe+work@gmail.com")
    end

    test "normalizes Googlemail addresses the same as Gmail" do
      %{id: id} = user_fixture(%{email: "johndoe@googlemail.com"})

      assert %User{id: ^id} =
               Accounts.get_user_by_email("john.doe@googlemail.com")

      assert %User{id: ^id} =
               Accounts.get_user_by_email("johndoe+test@googlemail.com")
    end

    test "does not apply Gmail normalization to other email providers" do
      user_fixture(%{email: "john.doe@example.com"})
      refute Accounts.get_user_by_email("johndoe@example.com")
    end

    test "finds Gmail users stored with dots in the database" do
      tag = Integer.to_string(System.unique_integer([:positive]))
      dotted_email = "user.#{tag}@gmail.com"
      canonical_email = "user#{tag}@gmail.com"

      %User{}
      |> Ecto.Changeset.change(%{
        email: dotted_email,
        first_name: "Legacy",
        last_name: "Dots",
        state: :active,
        role: :member
      })
      |> Repo.insert!()

      assert %User{email: ^dotted_email} =
               Accounts.get_user_by_email(canonical_email)

      assert %User{email: ^dotted_email} =
               Accounts.get_user_by_email(dotted_email)
    end
  end

  describe "get_user_by_phone_number/1" do
    test "returns nil for unknown phone number" do
      refute Accounts.get_user_by_phone_number("+15550000000")
      refute Accounts.get_user_by_phone_number("unknown")
    end

    test "returns user when phone number matches exactly (E.164)" do
      %{id: id} = user_fixture(%{phone_number: "+14159098268"})
      assert %User{id: ^id} = Accounts.get_user_by_phone_number("+14159098268")
    end

    test "returns user when phone number is US format with dashes" do
      %{id: id} = user_fixture(%{phone_number: "+14159098268"})
      assert %User{id: ^id} = Accounts.get_user_by_phone_number("415-909-8268")
    end

    test "returns user when phone number is US format without country code" do
      %{id: id} = user_fixture(%{phone_number: "+14159098268"})
      assert %User{id: ^id} = Accounts.get_user_by_phone_number("4159098268")
    end

    test "returns user when phone number has spaces (US)" do
      %{id: id} = user_fixture(%{phone_number: "+14159098268"})
      assert %User{id: ^id} = Accounts.get_user_by_phone_number("415 909 8268")
    end

    test "returns user for Nordic number stored as E.164 (Swedish)" do
      %{id: id} = user_fixture(%{phone_number: "+46701234567"})
      assert %User{id: ^id} = Accounts.get_user_by_phone_number("+46701234567")
      assert %User{id: ^id} = Accounts.get_user_by_phone_number("070-123 45 67")
    end

    test "returns user when exact DB match fails but a normalized variant matches (Finnish)" do
      %{id: id} = user_fixture(%{phone_number: "+358401234567"})

      # Covers find_user_by_normalized_phone/1 success path (accounts.ex ~75-85).
      assert %User{id: ^id} = Accounts.get_user_by_phone_number("040 123 4567")
    end
  end

  describe "passkey lifecycle" do
    test "get_user_passkeys returns empty list for user with no passkeys",
         %{} do
      user = user_fixture(%{phone_number: "+14159098268"})
      assert Accounts.get_user_passkeys(user) == []
    end

    test "create_user_passkey adds a passkey and get_user_passkeys returns it",
         %{} do
      user = user_fixture(%{phone_number: "+14159098268"})

      attrs = %{
        external_id: "cred-id-1",
        public_key: <<1, 2, 3>>,
        nickname: "Device 1"
      }

      assert {:ok, %UserPasskey{} = passkey} =
               Accounts.create_user_passkey(user, attrs)

      assert passkey.user_id == user.id
      assert passkey.external_id == "cred-id-1"
      assert passkey.sign_count == 0

      passkeys = Accounts.get_user_passkeys(user)
      assert length(passkeys) == 1
      assert hd(passkeys).id == passkey.id
    end

    test "update_passkey_sign_count updates sign_count and last_used_at", %{} do
      user = user_fixture(%{phone_number: "+14159098269"})

      {:ok, passkey} =
        Accounts.create_user_passkey(user, %{
          external_id: "cred-id-2",
          public_key: <<4, 5, 6>>
        })

      assert {:ok, updated} = Accounts.update_passkey_sign_count(passkey, 3)
      assert updated.sign_count == 3
      assert updated.last_used_at != nil
    end

    test "delete_user_passkey removes the passkey", %{} do
      user = user_fixture(%{phone_number: "+14159098270"})

      {:ok, passkey} =
        Accounts.create_user_passkey(user, %{
          external_id: "cred-id-3",
          public_key: <<7, 8, 9>>
        })

      assert {:ok, _} = Accounts.delete_user_passkey(passkey)
      assert Accounts.get_user_passkeys(user) == []
    end

    test "get_user_passkeys uses preloaded passkeys when association is loaded",
         %{} do
      user = user_fixture(%{phone_number: "+14159098274"})

      {:ok, passkey} =
        Accounts.create_user_passkey(user, %{
          external_id: "cred-preload-path",
          public_key: <<1>>
        })

      loaded = Accounts.get_user!(user.id, [:passkeys])
      assert Ecto.assoc_loaded?(loaded.passkeys)

      keys = Accounts.get_user_passkeys(loaded)
      assert length(keys) == 1
      assert hd(keys).id == passkey.id
    end

    test "should_show_passkey_prompt? is true when user has no passkeys and never dismissed",
         %{} do
      user = user_fixture(%{phone_number: "+14159098271"})
      assert user.passkey_prompt_dismissed_at == nil
      assert Accounts.should_show_passkey_prompt?(user) == true
    end

    test "should_show_passkey_prompt? is false when user has passkeys", %{} do
      user = user_fixture(%{phone_number: "+14159098272"})

      Accounts.create_user_passkey(user, %{
        external_id: "cred-id-4",
        public_key: <<0>>
      })

      assert Accounts.should_show_passkey_prompt?(user) == false
    end

    test "dismiss_passkey_prompt sets passkey_prompt_dismissed_at and should_show_passkey_prompt? is false",
         %{} do
      user = user_fixture(%{phone_number: "+14159098273"})
      assert Accounts.should_show_passkey_prompt?(user) == true

      assert {:ok, updated} = Accounts.dismiss_passkey_prompt(user)
      assert updated.passkey_prompt_dismissed_at != nil
      assert Accounts.should_show_passkey_prompt?(updated) == false
    end

    test "get_user_passkey_by_external_id returns passkey", %{} do
      user = user_fixture(%{phone_number: "+14159098274"})

      {:ok, passkey} =
        Accounts.create_user_passkey(user, %{
          external_id: "cred-unique-99",
          public_key: <<10>>
        })

      found = Accounts.get_user_passkey_by_external_id("cred-unique-99")
      assert found != nil
      assert found.id == passkey.id
    end
  end

  describe "verification codes" do
    test "generate_email_verification_code returns 6-digit string", %{} do
      code = Accounts.generate_email_verification_code()
      assert is_binary(code)
      assert String.length(code) == 6
      assert code =~ ~r/^\d{6}$/
    end

    test "store and get_email_verification_code roundtrip", %{} do
      user = user_fixture(%{phone_number: "+14159098280"})
      Accounts.store_email_verification_code(user, "123456", 600)
      assert Accounts.get_email_verification_code(user) == "123456"
    end

    test "get_email_verification_code returns nil when no code is stored",
         %{} do
      user = user_fixture(%{phone_number: unique_user_phone()})
      assert Accounts.get_email_verification_code(user) == nil
    end

    test "verify_email_verification_code returns ok when code matches", %{} do
      user = user_fixture(%{phone_number: "+14159098281"})
      Accounts.store_email_verification_code(user, "654321", 600)

      assert Accounts.verify_email_verification_code(user, "654321") ==
               {:ok, :verified}
    end

    test "verify_email_verification_code returns invalid_code when code does not match",
         %{} do
      user = user_fixture(%{phone_number: "+14159098282"})
      Accounts.store_email_verification_code(user, "111111", 600)

      assert Accounts.verify_email_verification_code(user, "999999") ==
               {:error, :invalid_code}
    end

    test "verify_email_verification_code accepts 000000 in dev/test", %{} do
      user = user_fixture(%{phone_number: "+14159098283"})
      # No code stored; in dev/test "000000" is accepted as bypass
      assert Accounts.verify_email_verification_code(user, "000000") ==
               {:ok, :verified}
    end

    test "remove_email_verification_code clears code", %{} do
      user = user_fixture(%{phone_number: "+14159098284"})
      Accounts.store_email_verification_code(user, "222222", 600)
      assert Accounts.get_email_verification_code(user) == "222222"
      Accounts.remove_email_verification_code(user)
      assert Accounts.get_email_verification_code(user) == nil
    end

    test "generate_and_store_email_verification_code returns stored code",
         %{} do
      user = user_fixture(%{phone_number: "+14159098285"})
      code = Accounts.generate_and_store_email_verification_code(user, 600)
      assert String.length(code) == 6
      assert Accounts.get_email_verification_code(user) == code
    end

    test "store and verify_phone_verification_code roundtrip", %{} do
      user = user_fixture(%{phone_number: "+14159098288"})
      Accounts.store_phone_verification_code(user, "555555", 600)

      assert Accounts.verify_phone_verification_code(user, "555555") ==
               {:ok, :verified}
    end

    test "verify_phone_verification_code accepts 000000 in dev/test", %{} do
      user = user_fixture(%{phone_number: "+14159098289"})

      assert Accounts.verify_phone_verification_code(user, "000000") ==
               {:ok, :verified}
    end

    test "generate_and_store_phone_verification_code stores and returns code",
         %{} do
      user = user_fixture(%{phone_number: "+14159098290"})
      code = Accounts.generate_and_store_phone_verification_code(user, 600)
      assert String.length(code) == 6

      assert Accounts.verify_phone_verification_code(user, code) ==
               {:ok, :verified}
    end
  end

  describe "family account" do
    test "get_family_group returns only user when no family", %{} do
      user = user_fixture(%{phone_number: "+14159098291"})
      group = Accounts.get_family_group(user)
      assert length(group) == 1
      assert hd(group).id == user.id
    end

    test "primary_user? and sub_account?", %{} do
      primary = user_fixture(%{phone_number: "+14159098292"})
      assert Accounts.primary_user?(primary) == true
      assert Accounts.sub_account?(primary) == false

      sub = user_fixture(%{phone_number: "+14159098293"})

      sub =
        sub
        |> Ecto.Changeset.change(%{})
        |> Ecto.Changeset.put_change(:primary_user_id, primary.id)
        |> Repo.update!()

      assert Accounts.primary_user?(sub) == false
      assert Accounts.sub_account?(sub) == true
    end

    test "get_family_group returns primary and sub_accounts", %{} do
      primary = user_fixture(%{phone_number: "+14159098294"})
      sub = user_fixture(%{phone_number: "+14159098295"})

      sub =
        sub
        |> Ecto.Changeset.change(%{})
        |> Ecto.Changeset.put_change(:primary_user_id, primary.id)
        |> Repo.update!()

      group = Accounts.get_family_group(primary)
      assert length(group) == 2
      ids = Enum.map(group, & &1.id)
      assert primary.id in ids
      assert sub.id in ids

      assert Accounts.get_primary_user(sub).id == primary.id
      sub_accounts = Accounts.get_sub_accounts(primary)
      assert length(sub_accounts) == 1
      assert hd(sub_accounts).id == sub.id
    end

    test "get_family_group_user_ids returns all family user ids", %{} do
      primary = user_fixture(%{phone_number: "+14159098296"})
      sub = user_fixture(%{phone_number: "+14159098297"})

      sub =
        sub
        |> Ecto.Changeset.change(%{})
        |> Ecto.Changeset.put_change(:primary_user_id, primary.id)
        |> Repo.update!()

      ids = Accounts.get_family_group_user_ids(primary)
      assert length(ids) == 2
      assert primary.id in ids
      assert sub.id in ids
    end

    test "remove_sub_account clears primary_user_id", %{} do
      primary = user_fixture(%{phone_number: "+14159098298"})
      sub = user_fixture(%{phone_number: "+14159098299"})

      sub =
        sub
        |> Ecto.Changeset.change(%{})
        |> Ecto.Changeset.put_change(:primary_user_id, primary.id)
        |> Repo.update!()

      assert {:ok, updated} = Accounts.remove_sub_account(sub, primary)
      assert updated.primary_user_id == nil

      group = Accounts.get_family_group(primary)
      assert length(group) == 1
      assert hd(group).id == primary.id
    end

    test "remove_sub_account syncs board volunteer billing for primary household" do
      primary = user_fixture(%{phone_number: "+14159098350"})
      sub = user_fixture(%{phone_number: "+14159098351"})

      sub =
        sub
        |> Ecto.Changeset.change(%{
          primary_user_id: primary.id,
          family_relationship: "child"
        })
        |> Repo.update!()

      {:ok, sub} = Accounts.assign_board_position(sub, :secretary)

      assert Ysc.Subscriptions.BoardVolunteerBilling.household_on_board?(
               primary
             )

      Application.put_env(:ysc, :board_volunteer_billing_sync_recorder, self())

      on_exit(fn ->
        Application.delete_env(:ysc, :board_volunteer_billing_sync_recorder)
      end)

      assert {:ok, _} = Accounts.remove_sub_account(sub, primary)

      refute Ysc.Subscriptions.BoardVolunteerBilling.household_on_board?(
               primary
             )

      assert_receive {:board_volunteer_sync, primary_id}
                     when primary_id == primary.id
    end

    test "remove_sub_account returns error when sub does not belong to primary",
         %{} do
      primary1 = user_fixture(%{phone_number: "+14159098300"})
      primary2 = user_fixture(%{phone_number: "+14159098301"})
      sub = user_fixture(%{phone_number: "+14159098302"})

      sub =
        sub
        |> Ecto.Changeset.change(%{})
        |> Ecto.Changeset.put_change(:primary_user_id, primary1.id)
        |> Repo.update!()

      assert {:error, :unauthorized} =
               Accounts.remove_sub_account(sub, primary2)
    end

    @tag process_caches: true
    test "remove_sub_account busts cached profile so membership access is revoked" do
      Cachex.clear(:ysc_cache)

      primary = user_with_lifetime_membership(%{phone_number: "+14159098303"})
      sub = user_fixture(%{phone_number: "+14159098304"})

      sub =
        sub
        |> Ecto.Changeset.change(%{
          primary_user_id: primary.id,
          family_relationship: "child"
        })
        |> Repo.update!()

      UserProfileCache.get_user!(sub.id, [])
      UserProfileCache.get_user!(primary.id, [:sub_accounts])

      cached_sub = Accounts.get_user!(sub.id, [])
      assert Accounts.has_active_membership?(cached_sub)

      assert {:ok, _} = Accounts.remove_sub_account(sub, primary)

      refreshed_sub = Accounts.get_user!(sub.id, [])
      assert is_nil(refreshed_sub.primary_user_id)
      refute Accounts.has_active_membership?(refreshed_sub)

      refreshed_primary = Accounts.get_user!(primary.id, [:sub_accounts])
      assert refreshed_primary.sub_accounts == []
    end
  end

  describe "get_user/2" do
    test "returns user by id" do
      user = user_fixture(%{phone_number: "+14159098268"})
      found = Accounts.get_user(user.id)
      assert found.id == user.id
    end

    test "returns nil for non-existent id" do
      refute Accounts.get_user(Ecto.ULID.generate())
    end

    test "preloads associations when specified" do
      user = user_fixture(%{phone_number: "+14159098268"})
      found = Accounts.get_user(user.id, [:subscriptions])
      assert Ecto.assoc_loaded?(found.subscriptions)
    end
  end

  describe "get_user_from_stripe_id/1" do
    test "returns user by stripe_id" do
      user = user_fixture(%{phone_number: "+14159098268"})

      user =
        user
        |> Ecto.Changeset.change(stripe_id: "cus_test123")
        |> Repo.update!()

      found = Accounts.get_user_from_stripe_id("cus_test123")
      assert found.id == user.id
    end

    test "returns nil for non-existent stripe_id" do
      refute Accounts.get_user_from_stripe_id("cus_nonexistent")
    end
  end

  describe "search_users/2" do
    test "searches users by name" do
      user =
        user_fixture(%{
          first_name: "John",
          last_name: "Doe",
          phone_number: "+14159098268"
        })

      results = Accounts.search_users("John")
      assert Enum.any?(results, &(&1.id == user.id))
    end

    test "searches users by email" do
      user =
        user_fixture(%{
          email: "john.doe@example.com",
          phone_number: "+14159098268"
        })

      results = Accounts.search_users("john.doe@example.com")
      assert Enum.any?(results, &(&1.id == user.id))
    end

    test "respects limit option" do
      for i <- 1..15 do
        # Generate valid phone numbers (US format: +1XXXXXXXXXX, 11 digits total)
        phone_suffix = String.pad_leading(Integer.to_string(i), 2, "0")

        user_fixture(%{
          first_name: "John#{i}",
          phone_number: "+141590982#{phone_suffix}"
        })
      end

      results = Accounts.search_users("John", limit: 10)
      assert length(results) <= 10
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email_and_password(
               "unknown@example.com",
               "hello world!"
             )
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture(%{phone_number: "+14159098268"})
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture(%{phone_number: "+14159098268"})

      assert %User{id: ^id} =
               Accounts.get_user_by_email_and_password(
                 user.email,
                 valid_user_password()
               )
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(Ecto.ULID.generate())
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture(%{phone_number: "+14159098268"})
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "has_active_membership?/1" do
    test "returns false for user without membership" do
      user = user_fixture(%{phone_number: "+14159098268"})
      refute Accounts.has_active_membership?(user)
    end

    test "returns true for user with lifetime membership" do
      user = user_fixture(%{phone_number: "+14159098268"})

      user =
        user
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Repo.update!()
        |> Repo.reload!()

      assert Accounts.has_active_membership?(user)
    end
  end

  describe "has_lifetime_membership?/1" do
    test "returns true when lifetime_membership_awarded_at is set" do
      user = user_fixture(%{phone_number: "+14159098268"})

      user =
        user
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Repo.update!()
        |> Repo.reload!()

      assert Accounts.has_lifetime_membership?(user)
    end

    test "returns false when lifetime_membership_awarded_at is nil" do
      user = user_fixture(%{phone_number: "+14159098268"})
      refute Accounts.has_lifetime_membership?(user)
    end
  end

  describe "list_paginated_users/2" do
    test "returns paginated users" do
      _user1 = user_fixture(%{phone_number: "+14159098268"})
      _user2 = user_fixture(%{phone_number: "+14159098269"})

      params = %{page: 1, page_size: 10}
      assert {:ok, {users, meta}} = Accounts.list_paginated_users(params)

      assert is_list(users)
      assert meta.current_page == 1
      assert meta.page_size == 10
    end

    test "filters by search term" do
      user = user_fixture(%{first_name: "John", phone_number: "+14159098268"})
      _other = user_fixture(%{first_name: "Jane", phone_number: "+14159098269"})

      params = %{page: 1, page_size: 10}

      assert {:ok, {users, _meta}} =
               Accounts.list_paginated_users(params, "John")

      assert Enum.any?(users, &(&1.id == user.id))
    end

    test "empty search term delegates to list_paginated_users/1" do
      _user = user_fixture(%{phone_number: "+14159098271"})
      params = %{page: 1, page_size: 10}

      assert {:ok, {users_a, meta_a}} = Accounts.list_paginated_users(params)

      assert {:ok, {users_b, meta_b}} =
               Accounts.list_paginated_users(params, "")

      assert length(users_a) == length(users_b)
      assert meta_a.total_count == meta_b.total_count
    end

    test "multi-column order_by with membership_type restores sort metadata at original index" do
      _user = user_fixture(%{phone_number: "+14159098268"})

      # membership_type is at index 1 — after last_name.
      params = %{
        "page" => "1",
        "page_size" => "10",
        "order_by" => ["last_name", "membership_type"],
        "order_directions" => ["asc", "desc"]
      }

      assert {:ok, {_users, meta}} = Accounts.list_paginated_users(params)

      # membership_type must be restored at index 1, preserving last_name at 0.
      assert meta.flop.order_by == [:last_name, :membership_type]
      assert meta.flop.order_directions == [:asc, :desc]
    end

    test "membership_type sort-only restores metadata at index 0 ahead of Flop defaults" do
      _user = user_fixture(%{phone_number: "+14159098270"})

      params = %{
        "page" => "1",
        "page_size" => "10",
        "order_by" => ["membership_type"],
        "order_directions" => ["asc"]
      }

      assert {:ok, {_users, meta}} = Accounts.list_paginated_users(params)

      # With membership_type stripped, Flop falls back to its default order
      # ([:first_name, :last_name]). After restoration, membership_type is
      # prepended at index 0 to reflect the user's original sort intent.
      assert meta.flop.order_by == [:membership_type, :first_name, :last_name]
      assert meta.flop.order_directions == [:asc, :asc, :asc]
    end

    test "list_paginated_users/1 returns error for invalid Flop params" do
      assert {:error, %Flop.Meta{errors: errors}} =
               Accounts.list_paginated_users(%{"limit" => "not_a_number"})

      assert Keyword.has_key?(errors, :limit)
    end

    test "list_paginated_users/2 with nil search_term delegates to list_paginated_users/1" do
      _user = user_fixture(%{phone_number: "+14159098273"})
      params = %{page: 1, page_size: 10}

      assert {:ok, {users_a, meta_a}} = Accounts.list_paginated_users(params)

      assert {:ok, {users_b, meta_b}} =
               Accounts.list_paginated_users(params, nil)

      assert length(users_a) == length(users_b)
      assert meta_a.total_count == meta_b.total_count
    end
  end

  describe "update_user_profile/2" do
    test "updates user profile" do
      user = user_fixture(%{phone_number: "+14159098268"})
      attrs = %{first_name: "Updated Name"}

      assert {:ok, updated} = Accounts.update_user_profile(user, attrs)
      assert updated.first_name == "Updated Name"
    end
  end

  describe "update_notification_preferences/2" do
    test "updates notification preferences (newsletter state lives in newsletter_subscribers)" do
      user = user_fixture(%{phone_number: "+14159098268"})

      attrs = %{
        "newsletter_notifications" => "false",
        "account_notifications" => "true",
        "event_notifications" => "true",
        "event_notifications_sms" => "false",
        "account_notifications_sms" => "false"
      }

      assert {:ok, updated} =
               Accounts.update_notification_preferences(user, attrs)

      # Newsletter preference is synced to newsletter_subscribers by the LiveView; here we only assert update succeeds
      assert updated.id == user.id
    end
  end

  describe "update_billing_address/2" do
    test "updates billing address" do
      user = user_fixture(%{phone_number: "+14159098268"})

      attrs = %{
        "address" => "123 New St",
        "city" => "San Francisco",
        "postal_code" => "94105",
        "country" => "US"
      }

      assert {:ok, _updated} = Accounts.update_billing_address(user, attrs)
    end
  end

  describe "get_billing_address/1" do
    test "returns billing address for user" do
      user = user_fixture(%{phone_number: "+14159098268"})
      address = Accounts.get_billing_address(user)
      # May be nil if no address set
      assert is_nil(address) || is_struct(address, Ysc.Accounts.Address)
    end
  end

  describe "register_user/1" do
    test "requires email, first_name and last_name to be set" do
      {:error, changeset} = Accounts.register_user(%{})

      assert %{
               email: ["can't be blank"],
               first_name: ["can't be blank"],
               last_name: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates email when given" do
      {:error, changeset} = Accounts.register_user(%{email: "not valid"})

      assert %{
               email: ["must have the @ sign and no spaces"],
               first_name: ["can't be blank"],
               last_name: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates maximum values for email and password for security" do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.register_user(%{email: too_long, password: too_long})

      assert "should be at most 160 character(s)" in errors_on(changeset).email

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "validates email uniqueness" do
      %{email: email} = user_fixture(%{phone_number: "+14159098268"})

      {:error, changeset} =
        Accounts.register_user(%{
          email: email,
          phone_number: "+14159098260",
          first_name: "John",
          last_name: "Doe",
          password: "valid password"
        })

      assert "has already been taken" in errors_on(changeset).email

      # Now try with the upper cased email too, to check that email case is ignored.
      {:error, changeset} =
        Accounts.register_user(%{
          email: String.upcase(email),
          phone_number: "+14159098260",
          first_name: "John",
          last_name: "Doe",
          password: "valid password"
        })

      assert "has already been taken" in errors_on(changeset).email
    end

    test "prevents duplicate Gmail signups with dots in email" do
      user_fixture(%{email: "johndoe@gmail.com", phone_number: "+14159098268"})

      {:error, changeset} =
        Accounts.register_user(%{
          email: "john.doe@gmail.com",
          phone_number: "+14159098260",
          first_name: "John",
          last_name: "Doe",
          password: "valid password"
        })

      assert "has already been taken" in errors_on(changeset).email
    end

    test "prevents duplicate Gmail signups with plus-addressing" do
      user_fixture(%{email: "testuser@gmail.com", phone_number: "+14159098268"})

      {:error, changeset} =
        Accounts.register_user(%{
          email: "testuser+tag@gmail.com",
          phone_number: "+14159098260",
          first_name: "Test",
          last_name: "User",
          password: "valid password"
        })

      assert "has already been taken" in errors_on(changeset).email
    end

    test "prevents duplicate Gmail signups with dots and plus-addressing combined" do
      user_fixture(%{email: "johndoe@gmail.com", phone_number: "+14159098268"})

      {:error, changeset} =
        Accounts.register_user(%{
          email: "john.doe+test@gmail.com",
          phone_number: "+14159098260",
          first_name: "John",
          last_name: "Doe",
          password: "valid password"
        })

      assert "has already been taken" in errors_on(changeset).email
    end

    test "normalizes Gmail email when registering new user" do
      {:ok, user} =
        Accounts.register_user(
          valid_user_attributes(%{
            email: "john.doe+test@gmail.com",
            phone_number: "+14159098268"
          })
        )

      assert user.email == "johndoe@gmail.com"
    end

    test "does not apply Gmail normalization to non-Gmail addresses" do
      {:ok, user} =
        Accounts.register_user(
          valid_user_attributes(%{
            email: "john.doe+test@example.com",
            phone_number: "+14159098268"
          })
        )

      assert user.email == "john.doe+test@example.com"
    end

    test "registers users with a hashed password" do
      email = unique_user_email()

      {:ok, user} =
        Accounts.register_user(
          valid_user_attributes(%{
            email: email,
            phone_number: "+14159098268"
          })
        )

      assert user.email == email
      assert is_binary(user.hashed_password)
      assert is_nil(user.confirmed_at)
      assert is_nil(user.password)
    end
  end

  describe "change_user_registration/2" do
    test "returns a changeset" do
      assert %Ecto.Changeset{} =
               changeset = Accounts.change_user_registration(%User{})

      assert changeset.required == [:email, :first_name, :last_name]
    end

    test "allows fields to be set" do
      email = unique_user_email()
      password = valid_user_password()

      changeset =
        Accounts.change_user_registration(
          %User{},
          valid_user_attributes(%{
            email: email,
            password: password,
            phone_number: "+14159098268"
          })
        )

      assert changeset.valid?
      assert get_change(changeset, :email) == email
      assert get_change(changeset, :password) == password
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "change_user_email/2" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "apply_user_email/3" do
    setup do
      %{user: user_fixture(%{phone_number: "+14159098268"})}
    end

    test "requires email to change", %{user: user} do
      {:error, changeset} =
        Accounts.apply_user_email(user, valid_user_password(), %{})

      assert %{email: ["did not change"]} = errors_on(changeset)
    end

    test "validates email", %{user: user} do
      {:error, changeset} =
        Accounts.apply_user_email(user, valid_user_password(), %{
          email: "not valid"
        })

      assert %{email: ["must have the @ sign and no spaces"]} =
               errors_on(changeset)
    end

    test "validates maximum value for email for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.apply_user_email(user, valid_user_password(), %{
          email: too_long
        })

      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness", %{user: user} do
      %{email: email} = user_fixture(%{phone_number: "+14159098265"})
      password = valid_user_password()

      {:error, changeset} =
        Accounts.apply_user_email(user, password, %{email: email})

      assert "has already been taken" in errors_on(changeset).email
    end

    test "validates current password", %{user: user} do
      {:error, changeset} =
        Accounts.apply_user_email(user, "invalid", %{email: unique_user_email()})

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end

    test "applies the email without persisting it", %{user: user} do
      email = unique_user_email()

      {:ok, user} =
        Accounts.apply_user_email(user, valid_user_password(), %{email: email})

      assert user.email == email
      assert Accounts.get_user!(user.id).email != email
    end
  end

  describe "deliver_user_update_email_instructions/3" do
    setup do
      %{user: user_fixture(%{phone_number: "+14159098268"})}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(
            user,
            "current@example.com",
            url
          )
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)

      assert user_token =
               Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))

      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@example.com"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = user_fixture(%{phone_number: "+14159098268"})
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(
            %{user | email: email},
            user.email,
            url
          )
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{
      user: user,
      token: token,
      email: email
    } do
      assert {:ok, updated_user, ^email} =
               Accounts.update_user_email(user, token)

      assert updated_user.email != user.email
      assert updated_user.email == email
      assert updated_user.confirmed_at
      assert updated_user.confirmed_at != user.confirmed_at
      changed_user = Repo.get!(User, user.id)
      assert changed_user.email == email
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email with invalid token", %{user: user} do
      assert Accounts.update_user_email(user, "oops") == :error
      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if user email changed", %{
      user: user,
      token: token
    } do
      assert Accounts.update_user_email(
               %{user | email: "current@example.com"},
               token
             ) == :error

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if token expired", %{user: user, token: token} do
      {1, nil} =
        Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert Accounts.update_user_email(user, token) == :error
      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "change_user_password/2" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} =
               changeset = Accounts.change_user_password(%User{})

      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_user_password(%User{}, %{
          "password" => "new valid password"
        })

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_user_password/3" do
    setup do
      %{user: user_fixture(%{phone_number: "+14159098268"})}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: [
                 "Passwords don't match. Please enter the same password in both fields."
               ]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: too_long
        })

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "validates current password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, "invalid", %{
          password: valid_user_password()
        })

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end

    test "updates the password", %{user: user} do
      {:ok, user} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: "new valid password"
        })

      assert is_nil(user.password)

      assert Accounts.get_user_by_email_and_password(
               user.email,
               "new valid password"
             )
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, _} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: "new valid password"
        })

      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture(%{phone_number: "+14159098268"})}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture(%{phone_number: "+14159098267"}).id,
          context: "session"
        })
      end
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture(%{phone_number: "+14159098268"})
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert session_user = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      {1, nil} =
        Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture(%{phone_number: "+14159098268"})
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "deliver_user_reset_password_instructions/2" do
    setup do
      %{user: user_fixture(%{phone_number: "+14159098268"})}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)

      assert user_token =
               Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))

      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "reset_password"
    end
  end

  describe "get_user_by_reset_password_token/1" do
    setup do
      user = user_fixture(%{phone_number: "+14159098268"})

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      %{user: user, token: token}
    end

    test "returns the user with valid token", %{user: %{id: id}, token: token} do
      assert %User{id: ^id} = Accounts.get_user_by_reset_password_token(token)
      assert Repo.get_by(UserToken, user_id: id)
    end

    test "does not return the user with invalid token", %{user: user} do
      refute Accounts.get_user_by_reset_password_token("oops")
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not return the user if token expired", %{
      user: user,
      token: token
    } do
      {1, nil} =
        Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      refute Accounts.get_user_by_reset_password_token(token)
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "reset_user_password/2" do
    setup do
      %{user: user_fixture(%{phone_number: "+14159098268"})}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.reset_user_password(user, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: [
                 "Passwords don't match. Please enter the same password in both fields."
               ]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.reset_user_password(user, %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{user: user} do
      {:ok, updated_user} =
        Accounts.reset_user_password(user, %{password: "new valid password"})

      assert is_nil(updated_user.password)

      assert Accounts.get_user_by_email_and_password(
               user.email,
               "new valid password"
             )
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, _} =
        Accounts.reset_user_password(user, %{password: "new valid password"})

      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "sets password_set_at on the user", %{user: user} do
      {:ok, updated_user} =
        Accounts.reset_user_password(user, %{password: "new valid password"})

      assert %DateTime{} = updated_user.password_set_at
    end

    test "sets password_set_at when user previously had no password (oauth user)",
         %{} do
      user = oauth_user_fixture()
      assert is_nil(user.password_set_at)

      {:ok, updated_user} =
        Accounts.reset_user_password(user, %{password: "new valid password"})

      assert %DateTime{} = updated_user.password_set_at
    end

    test "updates password_set_at even when already set", %{user: user} do
      # Backdate password_set_at to the past so any new DateTime.utc_now() is
      # guaranteed to be strictly greater without sleeping
      original_set_at = DateTime.add(DateTime.utc_now(), -60, :second)

      {:ok, user_with_password_set} =
        user
        |> Ysc.Accounts.User.password_set_changeset(%{
          password_set_at: original_set_at
        })
        |> Ysc.Repo.update()

      assert %DateTime{} = user_with_password_set.password_set_at

      {:ok, updated_user} =
        Accounts.reset_user_password(user_with_password_set, %{
          password: "another new valid password"
        })

      assert %DateTime{} = updated_user.password_set_at

      assert DateTime.compare(updated_user.password_set_at, original_set_at) ==
               :gt
    end
  end

  describe "inspect/2 for the User module" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end

  describe "SignupApplication validation" do
    alias Ysc.Accounts.SignupApplication

    test "requires agreed_to_bylaws to be true" do
      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, %{
          membership_type: :single,
          membership_eligibility: ["born_in_scandinavia"],
          birth_date: ~D[1990-01-01],
          address: "123 Main St",
          city: "San Francisco",
          country: "US",
          postal_code: "94105",
          place_of_birth: "SE",
          citizenship: "SE",
          most_connected_nordic_country: "SE",
          agreed_to_bylaws: false
        })

      refute changeset.valid?

      assert %{
               agreed_to_bylaws: [
                 "Please check the box to confirm you agree to the bylaws"
               ]
             } =
               errors_on(changeset)
    end

    test "accepts agreed_to_bylaws when true" do
      changeset =
        SignupApplication.application_changeset(%SignupApplication{}, %{
          membership_type: :single,
          membership_eligibility: ["born_in_scandinavia"],
          birth_date: ~D[1990-01-01],
          address: "123 Main St",
          city: "San Francisco",
          country: "US",
          postal_code: "94105",
          place_of_birth: "SE",
          citizenship: "SE",
          most_connected_nordic_country: "SE",
          link_to_scandinavia: "Born in Stockholm",
          agreed_to_bylaws: true
        })

      assert changeset.valid?
    end
  end

  describe "board position history" do
    test "assign_board_position sets user board_position and creates an open history record" do
      user = user_fixture()
      assert user.board_position == nil

      assert {:ok, updated_user} =
               Accounts.assign_board_position(user, :president)

      assert updated_user.board_position == :president

      history = Accounts.list_board_position_history(updated_user)
      assert length(history) == 1
      [record] = history
      assert record.user_id == user.id
      assert record.position == :president
      assert record.ended_on == nil
      assert record.started_on == Date.utc_today()
    end

    test "assign_board_position when user already has a position closes old record and opens new one" do
      user = user_fixture()
      {:ok, user} = Accounts.assign_board_position(user, :president)
      today = Date.utc_today()

      assert {:ok, updated_user} =
               Accounts.assign_board_position(user, :treasurer)

      assert updated_user.board_position == :treasurer

      history = Accounts.list_board_position_history(updated_user)
      assert length(history) == 2

      open = Enum.find(history, &is_nil(&1.ended_on))
      closed = Enum.find(history, &(&1.ended_on == today))
      assert open.position == :treasurer
      assert open.started_on == today
      assert closed.position == :president
      assert closed.ended_on == today
    end

    test "remove_board_position clears user board_position and closes open history record" do
      user = user_fixture()
      {:ok, user} = Accounts.assign_board_position(user, :secretary)

      {:ok, user} =
        user
        |> Ecto.Changeset.change(%{
          board_bio: "Bio text cleared when leaving board."
        })
        |> Repo.update()

      today = Date.utc_today()

      assert {:ok, updated_user} = Accounts.remove_board_position(user)
      assert updated_user.board_position == nil
      assert updated_user.board_bio == nil

      history = Accounts.list_board_position_history(updated_user)
      assert length(history) == 1
      [record] = history
      assert record.position == :secretary
      assert record.ended_on == today
    end

    test "remove_board_position when user has no position is a no-op for history and clears user" do
      user = user_fixture()
      assert user.board_position == nil

      assert {:ok, updated_user} = Accounts.remove_board_position(user)
      assert updated_user.board_position == nil

      assert Accounts.list_board_position_history(updated_user) == []
    end

    test "list_board_position_history returns all records for user" do
      user = user_fixture()
      {:ok, user} = Accounts.assign_board_position(user, :president)
      {:ok, user} = Accounts.assign_board_position(user, :vice_president)
      {:ok, _user} = Accounts.assign_board_position(user, :treasurer)

      history = Accounts.list_board_position_history(user)
      assert length(history) == 3
      positions = Enum.map(history, & &1.position)
      assert :treasurer in positions
      assert :vice_president in positions
      assert :president in positions
      open = Enum.filter(history, &is_nil(&1.ended_on))
      assert length(open) == 1
      assert hd(open).position == :treasurer
    end

    test "update_user with board_position param records history" do
      admin = user_fixture(%{role: :admin})
      user = user_fixture()

      assert {:ok, updated_user} =
               Accounts.update_user(
                 user,
                 %{"board_position" => "president"},
                 admin
               )

      assert updated_user.board_position == :president
      history = Accounts.list_board_position_history(updated_user)
      assert length(history) == 1
      assert hd(history).position == :president
      assert hd(history).ended_on == nil
    end

    test "update_user with board_position changed from one to another records two history entries" do
      admin = user_fixture(%{role: :admin})
      user = user_fixture()

      {:ok, user} =
        Accounts.update_user(user, %{"board_position" => "president"}, admin)

      assert {:ok, updated_user} =
               Accounts.update_user(
                 user,
                 %{"board_position" => "treasurer"},
                 admin
               )

      assert updated_user.board_position == :treasurer
      history = Accounts.list_board_position_history(updated_user)
      assert length(history) == 2
      open = Enum.find(history, &is_nil(&1.ended_on))
      closed = Enum.find(history, &(&1.ended_on == Date.utc_today()))
      assert open.position == :treasurer
      assert closed.position == :president
    end

    test "update_user with board_position cleared records history with ended_on" do
      admin = user_fixture(%{role: :admin})
      user = user_fixture()

      {:ok, user} =
        Accounts.update_user(user, %{"board_position" => "secretary"}, admin)

      assert {:ok, updated_user} =
               Accounts.update_user(user, %{"board_position" => ""}, admin)

      assert updated_user.board_position == nil
      history = Accounts.list_board_position_history(updated_user)
      assert length(history) == 1
      assert hd(history).position == :secretary
      assert hd(history).ended_on == Date.utc_today()
    end
  end

  describe "user_has_password_in_db?/1" do
    test "returns true when user has a hashed password stored" do
      user = user_fixture(%{phone_number: "+14159098300"})
      assert Accounts.user_has_password_in_db?(user)
      assert Accounts.user_has_password_in_db?(user.id)
    end

    test "returns false for OAuth user without password" do
      user = oauth_user_fixture(%{phone_number: "+14159098301"})
      refute Accounts.user_has_password_in_db?(user)
    end
  end

  describe "get_user_by_email_for_passkey/1" do
    test "returns nil when email is unknown" do
      refute Accounts.get_user_by_email_for_passkey(
               "nope-#{System.unique_integer()}@example.com"
             )
    end

    test "returns user with passkeys preloaded" do
      user = user_fixture(%{phone_number: "+14159098302"})

      {:ok, _} =
        Accounts.create_user_passkey(user, %{
          external_id: "pk-email-test",
          public_key: <<1>>
        })

      found = Accounts.get_user_by_email_for_passkey(user.email)
      assert found.id == user.id
      assert Ecto.assoc_loaded?(found.passkeys)
      assert length(found.passkeys) == 1
    end
  end

  describe "should_show_passkey_prompt?/1 dismissal cooldown" do
    test "returns true when prompt was dismissed more than 30 days ago and user has no passkeys" do
      user = user_fixture(%{phone_number: "+14159098303"})
      assert {:ok, user} = Accounts.dismiss_passkey_prompt(user)

      old =
        user
        |> Ecto.Changeset.change(%{
          passkey_prompt_dismissed_at:
            DateTime.utc_now()
            |> DateTime.add(-31, :day)
            |> DateTime.truncate(:second)
        })
        |> Repo.update!()

      assert Accounts.should_show_passkey_prompt?(old) == true
    end
  end

  describe "list_bod_members/0" do
    test "returns board members with ordering fields" do
      u1 = user_fixture(%{phone_number: "+14159098304", last_name: "Alpha"})
      u2 = user_fixture(%{phone_number: "+14159098305", last_name: "Beta"})
      {:ok, _} = Accounts.assign_board_position(u1, :president)
      {:ok, _} = Accounts.assign_board_position(u2, :secretary)

      bod = Accounts.list_bod_members()
      emails = Enum.map(bod, & &1.email)
      assert u1.email in emails
      assert u2.email in emails
      assert Enum.all?(bod, &Map.has_key?(&1, :board_position))
    end
  end

  describe "get_pending_approval_users/0" do
    test "returns users in pending_approval state with registration_form preloaded" do
      pending =
        oauth_user_fixture(%{
          phone_number: "+14159098306",
          state: :pending_approval
        })

      users = Accounts.get_pending_approval_users()
      assert Enum.any?(users, &(&1.id == pending.id))
      assert Enum.all?(users, &(&1.state == :pending_approval))
    end
  end

  describe "list_pending_approval_users/1 and count_pending_approval_users/0" do
    test "limit returns oldest pending users first" do
      older =
        oauth_user_fixture(%{
          phone_number: "+14159098320",
          state: :pending_approval,
          inserted_at: ~U[2026-01-01 12:00:00Z]
        })

      newer =
        oauth_user_fixture(%{
          phone_number: "+14159098321",
          state: :pending_approval,
          inserted_at: ~U[2026-06-01 12:00:00Z]
        })

      preview = Accounts.list_pending_approval_users(limit: 1)
      assert length(preview) == 1
      assert hd(preview).id == older.id
      refute Enum.any?(preview, &(&1.id == newer.id))
    end

    test "count reflects all pending users regardless of list limit" do
      _pending1 =
        oauth_user_fixture(%{
          phone_number: "+14159098322",
          state: :pending_approval
        })

      _pending2 =
        oauth_user_fixture(%{
          phone_number: "+14159098323",
          state: :pending_approval
        })

      assert Accounts.count_pending_approval_users() >= 2
      assert length(Accounts.list_pending_approval_users(limit: 1)) == 1
    end
  end

  describe "revoke_user_session_by_id/2" do
    test "revokes session when encoded id matches a session token" do
      user = user_fixture(%{phone_number: "+14159098307"})
      token = Accounts.generate_user_session_token(user)
      encoded = Base.encode64(token)
      assert Accounts.revoke_user_session_by_id(user, encoded) == :ok
      refute Accounts.get_user_by_session_token(token)
    end

    test "returns error for invalid base64" do
      user = user_fixture(%{phone_number: "+14159098308"})
      assert Accounts.revoke_user_session_by_id(user, "@@@") == :error
    end
  end

  describe "mark_email_verified/1, mark_phone_verified/1, mark_password_set/1" do
    test "sets verification and password timestamps" do
      user = user_fixture(%{phone_number: "+14159098309"})

      assert {:ok, u1} = Accounts.mark_email_verified(user)
      assert u1.email_verified_at

      assert {:ok, u2} = Accounts.mark_phone_verified(u1)
      assert u2.phone_verified_at

      assert {:ok, u3} = Accounts.mark_password_set(u2)
      assert u3.password_set_at
    end
  end

  describe "post-migration onboarding" do
    test "needs_post_migration_onboarding? and complete_post_migration_onboarding/1" do
      user = oauth_user_fixture(%{phone_number: "+14159098310"})

      {:ok, user} =
        user
        |> Ecto.Changeset.change(%{
          post_migration_onboarding_completed_at: nil,
          email_verified_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update()

      assert Accounts.needs_post_migration_onboarding?(user)

      assert {:ok, done} = Accounts.complete_post_migration_onboarding(user)
      assert done.post_migration_onboarding_completed_at
      refute Accounts.needs_post_migration_onboarding?(done)
    end
  end

  describe "user notes" do
    test "create_user_note, list_user_notes, and list_user_notes_by_category" do
      admin = user_fixture(%{phone_number: "+14159098311", role: :admin})
      subject = user_fixture(%{phone_number: "+14159098312"})

      assert {:ok, note} =
               Accounts.create_user_note(
                 subject,
                 %{
                   "note" => "Reviewed application",
                   "category" => "general"
                 },
                 admin
               )

      assert note.user_id == subject.id

      notes = Accounts.list_user_notes(subject.id)
      assert length(notes) == 1
      assert hd(notes).id == note.id

      assert {:ok, _} =
               Accounts.create_user_note(
                 subject,
                 %{"note" => "Rejected", "category" => "rejection"},
                 admin
               )

      all_notes = Accounts.list_user_notes(subject.id)
      assert length(all_notes) == 2

      rejection_only =
        Accounts.list_user_notes_by_category(subject.id, :rejection)

      assert length(rejection_only) == 1
      assert hd(rejection_only).category == :rejection
    end
  end

  describe "get_signup_application_submission_date/1" do
    test "returns submit date and timezone from signup application" do
      user = user_fixture(%{phone_number: "+14159098313"})

      %{completed: completed} =
        signup_application_fixture(user, %{
          browser_timezone: "America/Los_Angeles"
        })

      assert %{submit_date: ^completed, timezone: "America/Los_Angeles"} =
               Accounts.get_signup_application_submission_date(user.id)
    end

    test "returns nil when user has no signup application" do
      user = user_fixture(%{phone_number: "+14159098314"})
      refute Accounts.get_signup_application_submission_date(user.id)
    end
  end

  describe "leave_family_membership/1" do
    test "clears primary link for a sub-account" do
      primary = user_fixture(%{phone_number: "+14159098315"})
      sub = user_fixture(%{phone_number: "+14159098316"})

      {:ok, sub} =
        sub
        |> Ecto.Changeset.change(%{
          primary_user_id: primary.id,
          family_relationship: "child"
        })
        |> Repo.update()

      assert {:ok, left} = Accounts.leave_family_membership(sub)
      assert is_nil(left.primary_user_id)
      assert is_nil(left.family_relationship)
    end

    test "returns error when user is not a sub-account" do
      primary = user_fixture(%{phone_number: "+14159098317"})

      assert Accounts.leave_family_membership(primary) ==
               {:error, :not_sub_account}
    end

    test "leave_family_membership syncs board volunteer billing for primary household" do
      primary = user_fixture(%{phone_number: "+14159098702"})
      sub = user_fixture(%{phone_number: "+14159098703"})

      {:ok, sub} =
        sub
        |> Ecto.Changeset.change(%{
          primary_user_id: primary.id,
          family_relationship: "child"
        })
        |> Repo.update()

      {:ok, sub} = Accounts.assign_board_position(sub, :treasurer)

      assert Ysc.Subscriptions.BoardVolunteerBilling.household_on_board?(
               primary
             )

      Application.put_env(:ysc, :board_volunteer_billing_sync_recorder, self())

      on_exit(fn ->
        Application.delete_env(:ysc, :board_volunteer_billing_sync_recorder)
      end)

      assert {:ok, _} = Accounts.leave_family_membership(sub)

      refute Ysc.Subscriptions.BoardVolunteerBilling.household_on_board?(
               primary
             )

      primary_id = primary.id
      assert_receive {:board_volunteer_sync, ^primary_id}
    end

    @tag process_caches: true
    test "leave_family_membership busts cached profile so membership access is revoked" do
      Cachex.clear(:ysc_cache)

      primary = user_with_lifetime_membership(%{phone_number: "+14159098318"})
      sub = user_fixture(%{phone_number: "+14159098319"})

      {:ok, sub} =
        sub
        |> Ecto.Changeset.change(%{
          primary_user_id: primary.id,
          family_relationship: "child"
        })
        |> Repo.update()

      UserProfileCache.get_user!(sub.id, [])

      cached_sub = Accounts.get_user!(sub.id, [])
      assert Accounts.has_active_membership?(cached_sub)

      assert {:ok, left} = Accounts.leave_family_membership(sub)
      assert is_nil(left.primary_user_id)

      refreshed_sub = Accounts.get_user!(sub.id, [])
      assert is_nil(refreshed_sub.primary_user_id)
      refute Accounts.has_active_membership?(refreshed_sub)
    end
  end

  describe "list_memberships/1 and get_membership_stats/0" do
    test "list_memberships returns a list" do
      assert is_list(Accounts.list_memberships())
    end

    test "list_memberships accepts type and pagination options" do
      assert is_list(
               Accounts.list_memberships(type: :family, limit: 3, offset: 0)
             )
    end

    test "get_membership_stats returns counts by category" do
      stats = Accounts.get_membership_stats()

      assert %{
               total: _,
               single: _,
               family: _,
               lifetime: _
             } = stats
    end

    test "load_admin_memberships_page returns stats matching get_membership_stats" do
      {stats, memberships} = Accounts.load_admin_memberships_page(limit: 500)
      list_stats = Accounts.get_membership_stats()

      assert stats == list_stats
      assert is_list(memberships)
      assert length(memberships) <= min(stats.total, 500)

      {stats_family, family_rows} =
        Accounts.load_admin_memberships_page(type: :family, limit: 500)

      assert stats_family == stats
      assert Enum.all?(family_rows, &(&1.type == :family))
      refute Enum.any?(family_rows, &(&1.type == :lifetime))
    end

    test "list_memberships applies SQL limit before loading membership rows" do
      for idx <- 1..30 do
        user_with_lifetime_membership(%{
          phone_number: unique_user_phone(),
          last_name:
            "SqlLimit#{String.pad_leading(Integer.to_string(idx), 2, "0")}"
        })
      end

      assert length(Accounts.list_memberships(limit: 5)) == 5
      assert length(Accounts.list_memberships(limit: 5, offset: 5)) == 5
    end

    test "get_membership_stats uses COUNT queries without subscription preloads" do
      for _ <- 1..10 do
        user_with_lifetime_membership(%{phone_number: unique_user_phone()})
      end

      subscription_preload_pattern = ~r/FROM "subscriptions".*user_id.*ANY/i

      {_stats, subscription_preload_count} =
        Ysc.QueryCounter.with_query_counter(
          fn -> Accounts.get_membership_stats() end,
          pattern: subscription_preload_pattern
        )

      assert subscription_preload_count == 0
    end

    test "list_memberships type :single excludes lifetime primaries" do
      lifetime_primary =
        user_with_lifetime_membership(%{phone_number: unique_user_phone()})

      single_primary =
        user_with_single_subscription(%{phone_number: unique_user_phone()})

      single_only = Accounts.list_memberships(type: :single, limit: 500)

      assert Enum.any?(single_only, fn m ->
               m.primary_user.id == single_primary.id
             end)

      refute Enum.any?(single_only, fn m ->
               m.primary_user.id == lifetime_primary.id
             end)
    end

    test "get_membership_stats reports zero family when family plan is unconfigured" do
      plans = Application.get_env(:ysc, :membership_plans)

      family_primary =
        user_with_family_subscription(%{phone_number: unique_user_phone()})

      try do
        Application.put_env(
          :ysc,
          :membership_plans,
          Enum.reject(plans, &(&1.id == :family))
        )

        stats = Accounts.get_membership_stats()
        assert stats.family == 0
        assert stats.single == stats.total - stats.lifetime

        assert Accounts.list_memberships(type: :family, limit: 500) == []

        assert Enum.any?(
                 Accounts.list_memberships(type: :single, limit: 500),
                 fn m ->
                   m.primary_user.id == family_primary.id
                 end
               )
      after
        Application.put_env(:ysc, :membership_plans, plans)
      end
    end

    test "get_membership_joins_ytd_comparison returns comparable YTD join stats" do
      cmp = Accounts.get_membership_joins_ytd_comparison()

      assert %{
               current_ytd_joins: a,
               prior_ytd_joins: b,
               prior_year_label: y,
               joins_ytd_change_percent: pct
             } = cmp

      assert a >= 0 and b >= 0
      assert y != ""
      assert pct == nil or is_integer(pct)
    end

    test "get_membership_stats and list_memberships include lifetime and family primaries" do
      lifetime_primary =
        user_with_lifetime_membership(%{phone_number: unique_user_phone()})

      family_primary =
        user_with_family_subscription(%{phone_number: unique_user_phone()})

      membership_plans = Application.get_env(:ysc, :membership_plans, [])
      family_plan = Enum.find(membership_plans, &(&1.id == :family))

      stats = Accounts.get_membership_stats()
      assert stats.lifetime >= 1
      if family_plan, do: assert(stats.family >= 1)

      memberships = Accounts.list_memberships(limit: 500)

      assert Enum.any?(memberships, fn m ->
               m.primary_user.id == lifetime_primary.id and m.type == :lifetime
             end)

      if family_plan do
        assert Enum.any?(memberships, fn m ->
                 m.primary_user.id == family_primary.id and m.type == :family
               end)

        family_only = Accounts.list_memberships(type: :family, limit: 500)

        assert Enum.any?(family_only, fn m ->
                 m.primary_user.id == family_primary.id
               end)

        refute Enum.any?(family_only, fn m ->
                 m.primary_user.id == lifetime_primary.id
               end)
      end
    end

    test "list_memberships classifies active subscription without items as single type" do
      primary =
        primary_with_active_subscription_no_items(%{
          phone_number: unique_user_phone()
        })

      assert Enum.any?(Accounts.list_memberships(limit: 500), fn m ->
               m.primary_user.id == primary.id and m.type == :single
             end)
    end

    test "list_memberships and get_membership_stats exclude primaries with only inactive subscriptions" do
      cancelled =
        user_with_cancelled_subscription(%{phone_number: unique_user_phone()})

      expired_period =
        user_with_expired_subscription(%{phone_number: unique_user_phone()})

      ended =
        user_with_past_ends_at_subscription(%{
          phone_number: unique_user_phone()
        })

      active =
        user_with_single_subscription(%{phone_number: unique_user_phone()})

      memberships = Accounts.list_memberships(limit: 500)

      refute Enum.any?(memberships, fn m ->
               m.primary_user.id == cancelled.id
             end)

      refute Enum.any?(memberships, fn m ->
               m.primary_user.id == expired_period.id
             end)

      refute Enum.any?(memberships, fn m -> m.primary_user.id == ended.id end)

      refute Accounts.has_active_membership?(cancelled)
      refute Accounts.has_active_membership?(expired_period)
      refute Accounts.has_active_membership?(ended)

      membership_plans = Application.get_env(:ysc, :membership_plans, [])

      if membership_plans != [] do
        assert Enum.any?(memberships, fn m -> m.primary_user.id == active.id end)
      end
    end
  end

  describe "coverage: search state, sessions, family branches" do
    test "search_users/2 with state: :pending_approval finds pending users only" do
      pending =
        oauth_user_fixture(%{
          phone_number: "+14159098401",
          first_name: "ZetaPendingSearch",
          state: :pending_approval
        })

      refute Enum.any?(
               Accounts.search_users("ZetaPendingSearch"),
               &(&1.id == pending.id)
             )

      assert Enum.any?(
               Accounts.search_users("ZetaPendingSearch",
                 state: :pending_approval
               ),
               &(&1.id == pending.id)
             )
    end

    test "revoke_user_session_by_id/2 returns error when token belongs to another user" do
      user_a = user_fixture(%{phone_number: "+14159098402"})
      user_b = user_fixture(%{phone_number: "+14159098403"})
      token = Accounts.generate_user_session_token(user_a)
      encoded = Base.encode64(token)

      assert Accounts.revoke_user_session_by_id(user_b, encoded) == :error
      assert Accounts.get_user_by_session_token(token).id == user_a.id
    end

    test "has_active_membership?/1 is true for sub-account when primary has lifetime membership" do
      primary =
        oauth_user_fixture(%{phone_number: "+14159098404"})
        |> Ecto.Changeset.change(%{
          lifetime_membership_awarded_at:
            DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update!()

      sub =
        oauth_user_fixture(%{phone_number: "+14159098405"})
        |> Ecto.Changeset.change(%{primary_user_id: primary.id})
        |> Repo.update!()

      assert Accounts.has_active_membership?(sub)
    end

    test "has_active_membership?/1 is true for sub-account when primary has active subscription" do
      primary = user_fixture(%{phone_number: unique_user_phone()})

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: primary.id,
          stripe_id:
            "sub_primary_subacct_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 365, :day)
        })

      assert {:ok, _} =
               Subscriptions.create_subscription_item(%{
                 subscription_id: subscription.id,
                 stripe_price_id: "price_primary_subacct",
                 stripe_product_id: "prod_primary_subacct",
                 stripe_id:
                   "si_primary_subacct_#{System.unique_integer([:positive])}",
                 quantity: 1
               })

      sub =
        user_fixture(%{phone_number: unique_user_phone()})
        |> Ecto.Changeset.change(%{primary_user_id: primary.id})
        |> Repo.update!()

      assert Accounts.has_active_membership?(sub)
    end

    test "get_primary_user/1 returns nil for a primary account" do
      primary = user_fixture(%{phone_number: "+14159098406"})
      assert Accounts.get_primary_user(primary) == nil
    end

    test "get_sub_accounts/1 queries DB when sub_accounts association is not loaded" do
      primary = user_fixture(%{phone_number: "+14159098407"})

      sub =
        oauth_user_fixture(%{phone_number: "+14159098408"})
        |> Ecto.Changeset.change(%{primary_user_id: primary.id})
        |> Repo.update!()

      primary_fresh = Repo.get!(User, primary.id)
      refute Ecto.assoc_loaded?(primary_fresh.sub_accounts)

      ids = Enum.map(Accounts.get_sub_accounts(primary_fresh), & &1.id)
      assert sub.id in ids
    end

    test "admin_link_user_to_family/3 returns cannot_link_self" do
      primary = user_fixture(%{phone_number: "+14159098409"})
      other = user_fixture(%{phone_number: "+14159098410"})

      assert {:error, :cannot_link_self} =
               Accounts.admin_link_user_to_family(primary, primary)

      assert {:error, :cannot_link_self} =
               Accounts.admin_link_user_to_family(other, other)
    end

    test "admin_link_user_to_family/3 returns not_primary_user when first user is a sub-account" do
      primary = user_fixture(%{phone_number: "+14159098411"})

      sub =
        oauth_user_fixture(%{phone_number: "+14159098412"})
        |> Ecto.Changeset.change(%{primary_user_id: primary.id})
        |> Repo.update!()

      victim = user_fixture(%{phone_number: "+14159098413"})

      assert {:error, :not_primary_user} =
               Accounts.admin_link_user_to_family(sub, victim)
    end

    test "admin_link_user_to_family/3 returns already_linked_to_family when target is a sub-account" do
      primary = user_fixture(%{phone_number: "+14159098414"})

      already_sub =
        oauth_user_fixture(%{phone_number: "+14159098415"})
        |> Ecto.Changeset.change(%{primary_user_id: primary.id})
        |> Repo.update!()

      other_primary = user_fixture(%{phone_number: "+14159098416"})

      assert {:error, :already_linked_to_family} =
               Accounts.admin_link_user_to_family(other_primary, already_sub)
    end

    test "admin_link_user_to_family/3 returns primary_must_have_family_or_lifetime when primary has no membership" do
      primary = user_fixture(%{phone_number: "+14159098500"})
      victim = user_fixture(%{phone_number: "+14159098501"})

      assert {:error, :primary_must_have_family_or_lifetime} =
               Accounts.admin_link_user_to_family(primary, victim)
    end

    test "admin_link_user_to_family/3 links child when primary has lifetime membership" do
      primary = user_with_lifetime_membership(%{phone_number: "+14159098502"})
      victim = user_fixture(%{phone_number: "+14159098503"})

      assert {:ok, linked} = Accounts.admin_link_user_to_family(primary, victim)
      assert linked.primary_user_id == primary.id
      assert linked.family_relationship == :child
    end

    test "admin_link_user_to_family/3 syncs board volunteer billing when linking a board member" do
      primary = user_with_lifetime_membership(%{phone_number: "+14159098700"})
      victim = user_fixture(%{phone_number: "+14159098701"})

      {:ok, victim} = Accounts.assign_board_position(victim, :secretary)

      refute Ysc.Subscriptions.BoardVolunteerBilling.household_on_board?(
               primary
             )

      Application.put_env(:ysc, :board_volunteer_billing_sync_recorder, self())

      on_exit(fn ->
        Application.delete_env(:ysc, :board_volunteer_billing_sync_recorder)
      end)

      assert {:ok, linked} = Accounts.admin_link_user_to_family(primary, victim)
      assert linked.primary_user_id == primary.id

      assert Ysc.Subscriptions.BoardVolunteerBilling.household_on_board?(
               primary
             )

      primary_id = primary.id
      assert_receive {:board_volunteer_sync, ^primary_id}
    end

    test "admin_link_user_to_family/3 links child when primary has family subscription" do
      primary = user_with_family_subscription(%{phone_number: "+14159098504"})
      victim = user_fixture(%{phone_number: "+14159098505"})

      membership_plans = Application.get_env(:ysc, :membership_plans, [])
      family_plan = Enum.find(membership_plans, &(&1.id == :family))

      if family_plan do
        assert {:ok, linked} =
                 Accounts.admin_link_user_to_family(primary, victim)

        assert linked.primary_user_id == primary.id
      else
        assert {:error, :primary_must_have_family_or_lifetime} =
                 Accounts.admin_link_user_to_family(primary, victim)
      end
    end

    test "admin_link_user_to_family/3 returns max_spouses_reached when a spouse already exists" do
      primary = user_with_lifetime_membership(%{phone_number: "+14159098506"})
      s1 = user_fixture(%{phone_number: "+14159098507"})
      s2 = user_fixture(%{phone_number: "+14159098508"})

      assert {:ok, _} =
               Accounts.admin_link_user_to_family(primary, s1,
                 relationship: :spouse
               )

      assert {:error, :max_spouses_reached} =
               Accounts.admin_link_user_to_family(primary, s2,
                 relationship: :spouse
               )
    end

    test "admin_link_user_to_family/3 returns max_sub_accounts_reached when primary has 10 children" do
      primary = user_with_lifetime_membership(%{phone_number: "+14159098509"})

      for i <- 1..10 do
        %User{}
        |> User.sub_account_registration_changeset(
          %{
            email: "sub#{i}_#{System.unique_integer()}@example.com",
            password: "password123456",
            first_name: "Sub",
            last_name: "User#{i}",
            phone_number:
              "+1415555#{String.pad_leading(Integer.to_string(4000 + i), 4, "0")}",
            date_of_birth: ~D[1990-01-01]
          },
          primary.id,
          hash_password: true,
          validate_email: true
        )
        |> Repo.insert!()
      end

      eleventh = user_fixture(%{phone_number: "+14159098620"})

      assert {:error, :max_sub_accounts_reached} =
               Accounts.admin_link_user_to_family(primary, eleventh)
    end

    test "search_users matches full name via first_name || last_name fragment" do
      user =
        user_fixture(%{
          first_name: "Bjorn",
          last_name: "Ironside",
          phone_number: "+14159098510"
        })

      assert Enum.any?(
               Accounts.search_users("Bjorn Ironside"),
               &(&1.id == user.id)
             )
    end

    test "update_newsletter_on_email_change unsubscribes old and subscribes new when old was subscribed" do
      user = user_fixture(%{phone_number: "+14159098511"})
      old_email = user.email
      new_email = unique_user_email()

      assert {:ok, _} =
               Newsletter.subscribe(old_email,
                 user_id: user.id,
                 first_name: user.first_name,
                 last_name: user.last_name,
                 source: "test",
                 metadata: %{}
               )

      assert Accounts.update_newsletter_on_email_change(
               user,
               old_email,
               new_email
             ) == :ok

      refute Newsletter.get_subscriber_by_email(old_email).subscribed
      subscriber = Newsletter.get_subscriber_by_email(new_email)
      assert subscriber.subscribed
      assert subscriber.user_id == user.id
    end

    test "update_newsletter_on_email_change skips new subscribe when old was not subscribed" do
      user = user_fixture(%{phone_number: "+14159098512"})
      old_email = user.email
      new_email = unique_user_email()

      # register_user subscribes the email; unsubscribe so was_subscribed is false
      assert {:ok, _} = Newsletter.unsubscribe(old_email)

      assert Accounts.update_newsletter_on_email_change(
               user,
               old_email,
               new_email
             ) == :ok

      refute match?(
               %{subscribed: true},
               Newsletter.get_subscriber_by_email(new_email)
             )
    end

    test "set_user_initial_password/2 sets password for user without current password" do
      user = oauth_user_fixture(%{phone_number: "+14159098513"})

      assert {:ok, updated} =
               Accounts.set_user_initial_password(user, %{
                 "password" => "new valid password",
                 "password_confirmation" => "new valid password"
               })

      assert Accounts.get_user_by_email_and_password(
               user.email,
               "new valid password"
             ).id ==
               updated.id
    end
  end

  describe "change_notification_preferences, change_billing_address, and auth delegates" do
    test "change_notification_preferences/2 returns a changeset" do
      user = user_fixture(%{phone_number: "+14159098600"})

      cs = Accounts.change_notification_preferences(user, %{})

      assert %Ecto.Changeset{} = cs
      assert cs.data.id == user.id
    end

    test "change_billing_address/2 merges user_id for address changeset" do
      user = user_fixture(%{phone_number: "+14159098601"})

      cs =
        Accounts.change_billing_address(user, %{
          "address" => "1 Test Way",
          "city" => "SF"
        })

      assert Ecto.Changeset.get_field(cs, :user_id) == user.id
    end

    test "get_billing_address/1 returns persisted address after update_billing_address/2" do
      user = user_fixture(%{phone_number: "+14159098602"})

      assert {:ok, _} =
               Accounts.update_billing_address(user, %{
                 "address" => "99 Billing Rd",
                 "city" => "Oakland",
                 "postal_code" => "94607",
                 "country" => "US"
               })

      user = Accounts.get_user!(user.id, [:billing_address])
      addr = Accounts.get_billing_address(user)
      assert addr != nil
      assert addr.address == "99 Billing Rd"
    end

    test "get_user_auth_history/2 delegates to AuthService and returns a list" do
      user = user_fixture(%{phone_number: "+14159098603"})
      assert [] = Accounts.get_user_auth_history(user, 10)
    end

    test "get_last_successful_login_datetime/1 returns nil when user has no login events" do
      user = user_fixture(%{phone_number: "+14159098604"})
      assert Accounts.get_last_successful_login_datetime(user) == nil
    end

    test "get_last_session_timeframe/1 returns nil when there is no session history" do
      user = user_fixture(%{phone_number: "+14159098605"})
      assert Accounts.get_last_session_timeframe(user) == nil
    end

    test "can_send_family_invite?/1 is false without family or lifetime membership" do
      user = user_fixture(%{phone_number: "+14159098606"})
      refute Accounts.can_send_family_invite?(user)
    end

    test "can_send_family_invite?/1 is true for primary user with lifetime membership" do
      user = user_with_lifetime_membership(%{phone_number: "+14159098607"})
      assert Accounts.can_send_family_invite?(user)
    end

    test "update_user_phone_and_sms/2 updates phone number" do
      user = user_fixture(%{phone_number: "+14159098608"})

      assert {:ok, updated} =
               Accounts.update_user_phone_and_sms(user, %{
                 "phone_number" => "+14155559876"
               })

      assert updated.phone_number == "+14155559876"
    end
  end

  describe "authorization and signup application access" do
    test "update_user/3 returns unauthorized when member updates another user" do
      member = user_fixture(%{phone_number: unique_user_phone()})
      other = user_fixture(%{phone_number: unique_user_phone()})

      assert {:error, :unauthorized} =
               Accounts.update_user(other, %{"first_name" => "X"}, member)
    end

    test "update_user_with_address/3 returns unauthorized when member updates another user" do
      member = user_fixture(%{phone_number: unique_user_phone()})
      other = user_fixture(%{phone_number: unique_user_phone()})

      assert {:error, :unauthorized} =
               Accounts.update_user_with_address(
                 other,
                 %{"first_name" => "Y"},
                 member
               )
    end

    test "get_signup_application_from_user_id!/3 returns application for admin" do
      subject = user_fixture(%{phone_number: unique_user_phone()})
      admin = user_fixture(%{role: :admin, phone_number: unique_user_phone()})
      _app = signup_application_fixture(subject)

      assert %Ysc.Accounts.SignupApplication{} =
               Accounts.get_signup_application_from_user_id!(
                 subject.id,
                 admin,
                 []
               )
    end

    test "get_signup_application_from_user_id!/3 preloads requested associations" do
      subject = user_fixture(%{phone_number: unique_user_phone()})
      admin = user_fixture(%{role: :admin, phone_number: unique_user_phone()})
      _app = signup_application_fixture(subject)

      app =
        Accounts.get_signup_application_from_user_id!(subject.id, admin, [
          :user
        ])

      assert app.user_id == subject.id
      assert Ecto.assoc_loaded?(app.user)
      assert app.user.id == subject.id
    end

    test "get_signup_application_from_user_id!/3 returns error when member requests another user's application" do
      subject = user_fixture(%{phone_number: unique_user_phone()})
      member = user_fixture(%{phone_number: unique_user_phone()})
      _app = signup_application_fixture(subject)

      assert {:error, :unauthorized} =
               Accounts.get_signup_application_from_user_id!(
                 subject.id,
                 member,
                 []
               )
    end
  end

  describe "deliver_application_submitted_notification/1" do
    test "inserts EmailNotifier job for application_submitted template", %{} do
      user = user_fixture(%{phone_number: unique_user_phone()})

      assert %Oban.Job{args: args} =
               Accounts.deliver_application_submitted_notification(user)

      assert args["template"] == "application_submitted"
      assert args["recipient"] == user.email
    end
  end

  describe "create_user_note/3 validation" do
    test "returns error when note is empty", %{} do
      admin = user_fixture(%{role: :admin, phone_number: unique_user_phone()})
      subject = user_fixture(%{phone_number: unique_user_phone()})

      assert {:error, %Ecto.Changeset{} = cs} =
               Accounts.create_user_note(
                 subject,
                 %{"note" => "", "category" => "general"},
                 admin
               )

      refute cs.valid?
    end
  end

  describe "set_user_initial_password/2 errors" do
    test "returns changeset error for password too short", %{} do
      user = oauth_user_fixture(%{phone_number: unique_user_phone()})

      assert {:error, %Ecto.Changeset{} = cs} =
               Accounts.set_user_initial_password(user, %{
                 "password" => "short",
                 "password_confirmation" => "short"
               })

      assert cs.errors[:password]
    end
  end

  describe "list_paginated_users/1 membership filter" do
    test "filters to lifetime members when membership_type filter is lifetime" do
      phone = unique_user_phone()
      _lifetime = user_with_lifetime_membership(%{phone_number: phone})

      params = %{
        "page" => "1",
        "page_size" => "50",
        "filters" => %{
          "0" => %{"field" => "membership_type", "value" => "lifetime"}
        }
      }

      assert {:ok, {users, _meta}} = Accounts.list_paginated_users(params)

      assert Enum.any?(users, fn u ->
               not is_nil(u.lifetime_membership_awarded_at)
             end)
    end

    test "filters to single-plan members when membership_type filter is single" do
      membership_plans = Application.get_env(:ysc, :membership_plans, [])
      single_plan = Enum.find(membership_plans, &(&1.id == :single))

      if single_plan do
        single_user =
          user_with_single_subscription(%{phone_number: unique_user_phone()})

        params = %{
          "page" => "1",
          "page_size" => "50",
          "filters" => %{
            "0" => %{"field" => "membership_type", "value" => "single"}
          }
        }

        assert {:ok, {users, _meta}} = Accounts.list_paginated_users(params)

        assert Enum.any?(users, &(&1.id == single_user.id))
      end
    end

    test "does not include upgraded user in single filter when they now have family membership" do
      membership_plans = Application.get_env(:ysc, :membership_plans, [])
      single_plan = Enum.find(membership_plans, &(&1.id == :single))
      family_plan = Enum.find(membership_plans, &(&1.id == :family))

      if single_plan && family_plan do
        user = user_fixture(%{phone_number: unique_user_phone()})

        # Create one subscription with a single item (as if the user signed up for single)
        # AND a family item (as if they upgraded but the old item was not cleaned up).
        # This simulates the stale-item scenario after a plan upgrade.
        {:ok, subscription} =
          Subscriptions.create_subscription(%{
            user_id: user.id,
            stripe_id: "sub_upgrade_test_#{System.unique_integer()}",
            stripe_status: "active",
            name: "Membership",
            current_period_end: DateTime.add(DateTime.utc_now(), 365, :day)
          })

        {:ok, _single_item} =
          Subscriptions.create_subscription_item(%{
            subscription_id: subscription.id,
            stripe_price_id: single_plan.stripe_price_id,
            stripe_product_id: "prod_single_stale",
            stripe_id: "si_stale_single_#{System.unique_integer()}",
            quantity: 1
          })

        {:ok, _family_item} =
          Subscriptions.create_subscription_item(%{
            subscription_id: subscription.id,
            stripe_price_id: family_plan.stripe_price_id,
            stripe_product_id: "prod_family_new",
            stripe_id: "si_new_family_#{System.unique_integer()}",
            quantity: 1
          })

        single_params = %{
          "page" => "1",
          "page_size" => "100",
          "filters" => %{
            "0" => %{"field" => "membership_type", "value" => "single"}
          }
        }

        family_params = %{
          "page" => "1",
          "page_size" => "100",
          "filters" => %{
            "0" => %{"field" => "membership_type", "value" => "family"}
          }
        }

        assert {:ok, {single_users, _}} =
                 Accounts.list_paginated_users(single_params)

        assert {:ok, {family_users, _}} =
                 Accounts.list_paginated_users(family_params)

        refute Enum.any?(single_users, &(&1.id == user.id)),
               "User with both single and family items should NOT appear in single filter"

        assert Enum.any?(family_users, &(&1.id == user.id)),
               "User with both single and family items SHOULD appear in family filter"
      end
    end

    test "user appears in single filter after downgrade from family executes (single item only)" do
      membership_plans = Application.get_env(:ysc, :membership_plans, [])
      single_plan = Enum.find(membership_plans, &(&1.id == :single))
      family_plan = Enum.find(membership_plans, &(&1.id == :family))

      if single_plan && family_plan do
        user = user_fixture(%{phone_number: unique_user_phone()})

        # After the scheduled downgrade executes, the webhook calls
        # update_subscription_items which inserts the new single item and
        # deletes the old family item. The DB ends up with only the single item.
        {:ok, subscription} =
          Subscriptions.create_subscription(%{
            user_id: user.id,
            stripe_id: "sub_downgrade_done_#{System.unique_integer()}",
            stripe_status: "active",
            name: "Membership",
            current_period_end: DateTime.add(DateTime.utc_now(), 365, :day)
          })

        {:ok, _single_item} =
          Subscriptions.create_subscription_item(%{
            subscription_id: subscription.id,
            stripe_price_id: single_plan.stripe_price_id,
            stripe_product_id: "prod_single_new",
            stripe_id: "si_single_new_#{System.unique_integer()}",
            quantity: 1
          })

        single_params = %{
          "page" => "1",
          "page_size" => "100",
          "filters" => %{
            "0" => %{"field" => "membership_type", "value" => "single"}
          }
        }

        family_params = %{
          "page" => "1",
          "page_size" => "100",
          "filters" => %{
            "0" => %{"field" => "membership_type", "value" => "family"}
          }
        }

        assert {:ok, {single_users, _}} =
                 Accounts.list_paginated_users(single_params)

        assert {:ok, {family_users, _}} =
                 Accounts.list_paginated_users(family_params)

        assert Enum.any?(single_users, &(&1.id == user.id)),
               "User after completed downgrade SHOULD appear in single filter"

        refute Enum.any?(family_users, &(&1.id == user.id)),
               "User after completed downgrade should NOT appear in family filter"
      end
    end

    test "user still appears in family filter while downgrade is only scheduled (family item still active)" do
      membership_plans = Application.get_env(:ysc, :membership_plans, [])
      single_plan = Enum.find(membership_plans, &(&1.id == :single))
      family_plan = Enum.find(membership_plans, &(&1.id == :family))

      if single_plan && family_plan do
        # The downgrade is scheduled for next renewal, but the subscription
        # still has the family item — user keeps family access until then.
        user =
          user_with_family_subscription(%{phone_number: unique_user_phone()})

        single_params = %{
          "page" => "1",
          "page_size" => "100",
          "filters" => %{
            "0" => %{"field" => "membership_type", "value" => "single"}
          }
        }

        family_params = %{
          "page" => "1",
          "page_size" => "100",
          "filters" => %{
            "0" => %{"field" => "membership_type", "value" => "family"}
          }
        }

        assert {:ok, {single_users, _}} =
                 Accounts.list_paginated_users(single_params)

        assert {:ok, {family_users, _}} =
                 Accounts.list_paginated_users(family_params)

        refute Enum.any?(single_users, &(&1.id == user.id)),
               "User with pending downgrade should NOT appear in single filter yet"

        assert Enum.any?(family_users, &(&1.id == user.id)),
               "User with pending downgrade SHOULD still appear in family filter"
      end
    end

    test "membership_type filter accepts a list of types (OR)" do
      membership_plans = Application.get_env(:ysc, :membership_plans, [])
      family_plan = Enum.find(membership_plans, &(&1.id == :family))

      lifetime_user =
        user_with_lifetime_membership(%{phone_number: unique_user_phone()})

      family_user =
        user_with_family_subscription(%{phone_number: unique_user_phone()})

      params = %{
        "page" => "1",
        "page_size" => "100",
        "filters" => %{
          "0" => %{
            "field" => "membership_type",
            "value" => ["lifetime", "family"]
          }
        }
      }

      assert {:ok, {users, _meta}} = Accounts.list_paginated_users(params)

      assert Enum.any?(users, &(&1.id == lifetime_user.id))

      if family_plan do
        assert Enum.any?(users, &(&1.id == family_user.id))
      end
    end
  end

  describe "list_paginated_users/2 sub-account primary_user preload" do
    test "preloads primary user and subscriptions for sub-accounts when primary has family membership" do
      membership_plans = Application.get_env(:ysc, :membership_plans, [])
      family_plan = Enum.find(membership_plans, &(&1.id == :family))

      if family_plan do
        primary =
          user_with_family_subscription(%{
            phone_number: unique_user_phone(),
            first_name: "PrimarySubPreload"
          })

        sub =
          user_fixture(%{
            phone_number: unique_user_phone(),
            first_name: "SubPreloadSearch"
          })
          |> Ecto.Changeset.change(%{primary_user_id: primary.id})
          |> Repo.update!()

        params = %{page: 1, page_size: 50}

        assert {:ok, {users, _meta}} =
                 Accounts.list_paginated_users(params, "SubPreloadSearch")

        found = Enum.find(users, &(&1.id == sub.id))
        assert found != nil
        assert %User{} = found.primary_user
        assert found.primary_user.id == primary.id
        assert Ecto.assoc_loaded?(found.primary_user.subscriptions)
      end
    end
  end

  describe "has_active_membership?/1 subscriptions not loaded" do
    test "loads subscriptions when struct has NotLoaded subscriptions" do
      user = user_fixture(%{phone_number: unique_user_phone()})

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_cov_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 365, :day)
        })

      assert {:ok, _} =
               Subscriptions.create_subscription_item(%{
                 subscription_id: subscription.id,
                 stripe_price_id: "price_test_cov",
                 stripe_product_id: "prod_test_cov",
                 stripe_id: "si_cov_#{System.unique_integer()}",
                 quantity: 1
               })

      fresh = Repo.get!(User, user.id)
      assert match?(%Ecto.Association.NotLoaded{}, fresh.subscriptions)
      assert Accounts.has_active_membership?(fresh)
    end
  end

  describe "update_default_payment_method/2" do
    test "sets the given payment method as the user's default" do
      user = user_fixture(%{phone_number: unique_user_phone()})

      pm_a =
        %PaymentMethod{
          user_id: user.id,
          provider: :stripe,
          provider_id: "pm_default_a_#{System.unique_integer([:positive])}",
          provider_customer_id:
            "cus_default_#{System.unique_integer([:positive])}",
          provider_type: "card",
          type: :card,
          last_four: "4242",
          exp_month: 12,
          exp_year: 2030,
          display_brand: "visa",
          is_default: true
        }
        |> Repo.insert!()

      pm_b =
        %PaymentMethod{
          user_id: user.id,
          provider: :stripe,
          provider_id: "pm_default_b_#{System.unique_integer([:positive])}",
          provider_customer_id:
            "cus_default_#{System.unique_integer([:positive])}",
          provider_type: "card",
          type: :card,
          last_four: "0005",
          exp_month: 11,
          exp_year: 2031,
          display_brand: "mastercard",
          is_default: false
        }
        |> Repo.insert!()

      assert pm_a.is_default
      refute pm_b.is_default

      assert {:ok, _} = Accounts.update_default_payment_method(user, pm_b.id)

      pm_a = Repo.get!(PaymentMethod, pm_a.id)
      pm_b = Repo.get!(PaymentMethod, pm_b.id)
      refute pm_a.is_default
      assert pm_b.is_default
    end
  end

  describe "record_application_outcome/4" do
    test "approves pending application and activates user" do
      applicant =
        oauth_user_fixture(%{
          phone_number: unique_user_phone(),
          state: :pending_approval
        })

      application = signup_application_fixture(applicant)
      admin = user_fixture(%{role: :admin, phone_number: unique_user_phone()})

      assert {:ok, _} =
               Accounts.record_application_outcome(
                 :approved,
                 applicant,
                 application,
                 admin
               )

      assert Repo.get!(User, applicant.id).state == :active

      reviewed =
        Repo.get!(Ysc.Accounts.SignupApplication, application.id)

      assert reviewed.review_outcome == :approved
      assert reviewed.reviewed_by_user_id == admin.id
    end

    test "rejects pending application" do
      applicant =
        oauth_user_fixture(%{
          phone_number: unique_user_phone(),
          state: :pending_approval
        })

      application = signup_application_fixture(applicant)
      admin = user_fixture(%{role: :admin, phone_number: unique_user_phone()})

      assert :ok =
               Accounts.record_application_outcome(
                 :rejected,
                 applicant,
                 application,
                 admin
               )

      assert Repo.get!(User, applicant.id).state == :rejected

      reviewed =
        Repo.get!(Ysc.Accounts.SignupApplication, application.id)

      assert reviewed.review_outcome == :rejected
    end
  end

  describe "list_paginated_users/2 multi-word fuzzy search" do
    test "finds users by two-word full name (John Doe)" do
      user =
        user_fixture(%{
          first_name: "John",
          last_name: "Doe",
          phone_number: unique_user_phone()
        })

      _other =
        user_fixture(%{
          first_name: "Jane",
          last_name: "Doe",
          phone_number: unique_user_phone()
        })

      params = %{page: 1, page_size: 20}

      assert {:ok, {users, _meta}} =
               Accounts.list_paginated_users(params, "John Doe")

      assert Enum.any?(users, &(&1.id == user.id))
    end
  end

  describe "register_user/1 with signup application (birth_date and billing address)" do
    test "persists date of birth from signup application and creates billing address" do
      email = unique_user_email()
      phone = unique_user_phone()

      attrs =
        valid_user_attributes(%{
          email: email,
          phone_number: phone,
          registration_form: %{
            membership_type: "single",
            membership_eligibility: ["born_in_scandinavia"],
            occupation: "Developer",
            birth_date: ~D[1991-06-15],
            address: "456 Nordic Ln",
            country: "USA",
            city: "Seattle",
            postal_code: "98101",
            place_of_birth: "Bergen",
            citizenship: "Norwegian",
            most_connected_nordic_country: "Norway",
            link_to_scandinavia: "Grandparents from Norway",
            agreed_to_bylaws: true,
            completed: DateTime.utc_now()
          }
        })

      assert {:ok, user} = Accounts.register_user(attrs)
      user = Repo.get!(User, user.id)

      assert user.date_of_birth == ~D[1991-06-15]

      assert %Ysc.Accounts.Address{} =
               address = Accounts.get_billing_address(user)

      assert address.address == "456 Nordic Ln"
      assert address.city == "Seattle"
    end
  end

  describe "has_active_membership?/1 sub-account without primary" do
    test "returns false when primary user cannot be loaded" do
      missing_primary_id = Ecto.ULID.generate()

      user = %User{
        id: Ecto.ULID.generate(),
        primary_user_id: missing_primary_id,
        primary_user: %Ecto.Association.NotLoaded{}
      }

      refute Accounts.has_active_membership?(user)
    end
  end

  describe "coverage — get_user_by_phone_number normalization edge cases" do
    test "returns nil when no user matches after normalization variants" do
      assert Accounts.get_user_by_phone_number("+999999999999999") == nil
    end
  end

  describe "coverage — register_user billing address from signup" do
    test "continues registration when billing address insert fails (city too long for Address schema)" do
      email = unique_user_email()
      long_city = String.duplicate("C", 101)

      attrs =
        valid_user_attributes(%{
          email: email,
          phone_number: unique_user_phone(),
          registration_form: %{
            membership_type: "single",
            membership_eligibility: ["born_in_scandinavia"],
            occupation: "Developer",
            birth_date: ~D[1991-06-15],
            address: "456 Nordic Ln",
            country: "USA",
            city: long_city,
            postal_code: "98101",
            place_of_birth: "Bergen",
            citizenship: "Norwegian",
            most_connected_nordic_country: "Norway",
            link_to_scandinavia: "Grandparents from Norway",
            agreed_to_bylaws: true,
            completed: DateTime.utc_now()
          }
        })

      assert {:ok, user} = Accounts.register_user(attrs)
      assert user.email == email
      assert Accounts.get_billing_address(user) == nil
    end
  end

  describe "coverage — has_active_membership? unexpected subscription assoc shape" do
    test "returns false when subscriptions is not loaded and not a list" do
      user = %User{
        id: Ecto.ULID.generate(),
        subscriptions: %{},
        lifetime_membership_awarded_at: nil
      }

      refute Accounts.has_active_membership?(user)
    end
  end

  describe "update_user/3 and update_user_with_address/3 validation errors" do
    test "returns changeset error when admin submits empty first_name" do
      admin = user_fixture(%{role: :admin, phone_number: unique_user_phone()})
      user = user_fixture(%{phone_number: unique_user_phone()})

      assert {:error, %Ecto.Changeset{} = cs} =
               Accounts.update_user(user, %{"first_name" => ""}, admin)

      assert cs.errors[:first_name]
    end

    test "returns changeset error when admin submits phone_number over max length" do
      admin = user_fixture(%{role: :admin, phone_number: unique_user_phone()})
      user = user_fixture(%{phone_number: unique_user_phone()})

      assert {:error, %Ecto.Changeset{} = cs} =
               Accounts.update_user_with_address(
                 user,
                 %{
                   "first_name" => user.first_name,
                   "last_name" => user.last_name,
                   "phone_number" => String.duplicate("1", 30)
                 },
                 admin
               )

      assert cs.errors[:phone_number]
    end
  end

  describe "update_user_profile/2 validation" do
    test "returns error when first_name is empty" do
      user = user_fixture(%{phone_number: unique_user_phone()})

      assert {:error, %Ecto.Changeset{} = cs} =
               Accounts.update_user_profile(user, %{
                 first_name: "",
                 last_name: "Doe"
               })

      assert cs.errors[:first_name]
    end
  end

  describe "update_billing_address/2 validation" do
    test "returns error when city exceeds max length" do
      user = user_fixture(%{phone_number: unique_user_phone()})

      assert {:error, %Ecto.Changeset{} = cs} =
               Accounts.update_billing_address(user, %{
                 "address" => "123 St",
                 "city" => String.duplicate("Y", 101),
                 "postal_code" => "94105",
                 "country" => "US"
               })

      assert cs.errors[:city]
    end
  end

  describe "get_user_by_session_token/1 membership cache" do
    test "skips subscription preload when membership cache has a value", %{} do
      user = user_fixture(%{phone_number: unique_user_phone()})
      token = Accounts.generate_user_session_token(user)

      assert {:ok, true} =
               Cachex.put(:ysc_cache, "membership:#{user.id}:active", :cached)

      on_exit(fn -> Cachex.del(:ysc_cache, "membership:#{user.id}:active") end)

      loaded = Accounts.get_user_by_session_token(token)
      assert loaded.id == user.id
      assert match?(%Ecto.Association.NotLoaded{}, loaded.subscriptions)
    end
  end

  describe "get_primary_user/1 with preloaded association" do
    test "returns primary struct when primary_user is already loaded", %{} do
      primary = user_fixture(%{phone_number: unique_user_phone()})

      sub =
        user_fixture(%{phone_number: unique_user_phone()})
        |> Ecto.Changeset.change(%{primary_user_id: primary.id})
        |> Repo.update!()

      sub = Repo.preload(sub, :primary_user)
      assert %User{id: id} = Accounts.get_primary_user(sub)
      assert id == primary.id
    end
  end

  describe "send_email_verification_code/4 and send_phone_verification_code/4" do
    test "uses target email and resend suffix in idempotency key for email",
         %{} do
      user = user_fixture(%{phone_number: unique_user_phone()})
      other_email = unique_user_email()

      Oban.Testing.with_testing_mode(:manual, fn ->
        Accounts.send_email_verification_code(
          user,
          "123456",
          "retry1",
          other_email
        )

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "recipient" => other_email,
            "idempotency_key" => "account_setup_verification_#{user.id}_retry1",
            "template" => "account_setup_verification"
          }
        )
      end)
    end

    test "uses to_phone and resend suffix for SMS verification", %{} do
      user = user_fixture(%{phone_number: unique_user_phone()})

      Oban.Testing.with_testing_mode(:manual, fn ->
        Accounts.send_phone_verification_code(
          user,
          "999999",
          "sms2",
          "+12065550001"
        )

        assert_enqueued(
          worker: YscWeb.Workers.SmsNotifier,
          args: %{
            "phone_number" => "12065550001",
            "idempotency_key" => "phone_verification_#{user.id}_sms2",
            "template" => "phone_verification"
          }
        )
      end)
    end
  end

  describe "list_paginated_users/1 membership filter none" do
    test "filters to users without active subscription when membership_type is none" do
      phone = unique_user_phone()
      _no_sub = user_fixture(%{phone_number: phone})

      params = %{
        "page" => "1",
        "page_size" => "50",
        "filters" => %{
          "0" => %{"field" => "membership_type", "value" => "none"}
        }
      }

      assert {:ok, {users, _meta}} = Accounts.list_paginated_users(params)

      assert Enum.all?(users, fn u ->
               is_nil(u.lifetime_membership_awarded_at) and
                 (u.subscriptions == [] or
                    not Enum.any?(u.subscriptions, &Ysc.Subscriptions.valid?/1))
             end)
    end
  end

  describe "list_paginated_users/2 multi-word search with explicit sort" do
    test "uses fuzzy multi-word query without rank when order_by is explicit" do
      user =
        user_fixture(%{
          first_name: "Alice",
          last_name: "Wonderland",
          phone_number: unique_user_phone()
        })

      params = %{
        "page" => "1",
        "page_size" => "20",
        "order_by" => ["last_name"],
        "order_directions" => ["asc"]
      }

      assert {:ok, {users, _meta}} =
               Accounts.list_paginated_users(params, "Alice Wonderland")

      assert Enum.any?(users, &(&1.id == user.id))
    end
  end

  describe "coverage — get_user_by_phone_number/1 and update_newsletter_on_email_change/3" do
    test "matches via normalize_phone_number_variants when lookup omits country code (E.164 first variant)" do
      phone = unique_user_phone()
      %{id: id} = user_fixture(%{phone_number: phone})
      national = String.slice(phone, 2..-1//1)

      assert %User{id: ^id} = Accounts.get_user_by_phone_number(national)
    end

    test "update_newsletter_on_email_change: old email with no subscriber row is treated as not subscribed" do
      user = user_fixture(%{phone_number: unique_user_phone()})

      old_email =
        "never-subscribed-#{System.unique_integer([:positive])}@example.com"

      new_email = unique_user_email()

      assert Accounts.update_newsletter_on_email_change(
               user,
               old_email,
               new_email
             ) == :ok

      refute Newsletter.get_subscriber_by_email(old_email)
    end
  end

  describe "create_billing_address_from_signup/1" do
    test "returns {:ok, nil} when signup application is missing required address fields" do
      email = unique_user_email()

      attrs =
        valid_user_attributes(%{
          email: email,
          phone_number: unique_user_phone(),
          registration_form: %{
            membership_type: "single",
            membership_eligibility: ["born_in_scandinavia"],
            occupation: "Developer",
            birth_date: ~D[1991-06-15],
            address: "456 Nordic Ln",
            country: "USA",
            city: "Seattle",
            postal_code: "98101",
            place_of_birth: "Bergen",
            citizenship: "Norwegian",
            most_connected_nordic_country: "Norway",
            link_to_scandinavia: "Grandparents from Norway",
            agreed_to_bylaws: true,
            completed: DateTime.utc_now()
          }
        })

      assert {:ok, user} = Accounts.register_user(attrs)

      user = Accounts.get_user!(user.id, [:registration_form, :billing_address])

      if addr = user.billing_address do
        Repo.delete!(addr)
      end

      # DB enforces NOT NULL on city; simulate incomplete data the function still handles.
      form = %{user.registration_form | city: nil}
      user = %{user | registration_form: form}

      assert Accounts.create_billing_address_from_signup(user) == {:ok, nil}
    end

    test "loads registration_form when association was not preloaded" do
      email = unique_user_email()

      attrs =
        valid_user_attributes(%{
          email: email,
          phone_number: unique_user_phone(),
          registration_form: %{
            membership_type: "single",
            membership_eligibility: ["born_in_scandinavia"],
            occupation: "Developer",
            birth_date: ~D[1991-06-15],
            address: "789 Nordic Ln",
            country: "USA",
            city: "Seattle",
            postal_code: "98101",
            place_of_birth: "Bergen",
            citizenship: "Norwegian",
            most_connected_nordic_country: "Norway",
            link_to_scandinavia: "Grandparents from Norway",
            agreed_to_bylaws: true,
            completed: DateTime.utc_now()
          }
        })

      assert {:ok, user} = Accounts.register_user(attrs)
      assert %Ysc.Accounts.Address{} = Accounts.get_billing_address(user)

      user = Repo.get!(User, user.id)
      refute Ecto.assoc_loaded?(user.registration_form)

      assert {:ok, %Ysc.Accounts.Address{}} =
               Accounts.create_billing_address_from_signup(user)
    end

    test "returns {:ok, nil} when registration_form is nil after preload" do
      user = oauth_user_fixture(%{phone_number: unique_user_phone()})
      user = Accounts.get_user!(user.id, [:registration_form])
      assert user.registration_form == nil
      assert Accounts.create_billing_address_from_signup(user) == {:ok, nil}
    end

    test "preloads and returns {:ok, nil} when user has no signup application (association not loaded)" do
      user = oauth_user_fixture(%{phone_number: unique_user_phone()})
      user = Repo.get!(User, user.id)
      refute Ecto.assoc_loaded?(user.registration_form)
      assert Accounts.create_billing_address_from_signup(user) == {:ok, nil}
    end
  end

  describe "format_board_position/1" do
    test "formats atom board positions" do
      assert Accounts.format_board_position(:vice_president) == "Vice President"

      assert Accounts.format_board_position(:clear_lake_cabin_master) ==
               "Clear Lake Cabin Master"
    end

    test "formats string board positions stored on published posts" do
      assert Accounts.format_board_position("vice_president") ==
               "Vice President"

      assert Accounts.format_board_position("member_outreach") ==
               "Member Outreach & Events"
    end

    test "title-cases unknown board position strings" do
      assert Accounts.format_board_position("zz_unknown_role") ==
               "Zz_unknown_role"
    end

    test "returns empty string for nil" do
      assert Accounts.format_board_position(nil) == ""
    end
  end
end
