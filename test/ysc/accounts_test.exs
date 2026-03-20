defmodule Ysc.AccountsTest do
  use Ysc.DataCase

  alias Ysc.Accounts
  alias Ysc.Repo

  import Ysc.AccountsFixtures
  alias Ysc.Accounts.{User, UserPasskey, UserToken}

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture(%{phone_number: "+14159098268"})
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
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

    test "verify_email_code accepts valid 6-digit code", %{} do
      user = user_fixture(%{phone_number: "+14159098286"})
      assert Accounts.verify_email_code(user, "123456") == {:ok, user}
      assert Accounts.verify_email_code(user, "000000") == {:ok, user}
    end

    test "verify_email_code rejects invalid format", %{} do
      user = user_fixture(%{phone_number: "+14159098287"})

      assert Accounts.verify_email_code(user, "12345") ==
               {:error, :invalid_code}

      assert Accounts.verify_email_code(user, "1234567") ==
               {:error, :invalid_code}

      assert Accounts.verify_email_code(user, "12a456") ==
               {:error, :invalid_code}
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
               password_confirmation: ["does not match password"]
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

  describe "deliver_user_confirmation_instructions/2" do
    setup do
      %{user: user_fixture(%{phone_number: "+14159098268"})}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)

      assert user_token =
               Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))

      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "confirm"
    end
  end

  describe "confirm_user/1" do
    setup do
      user = user_fixture(%{phone_number: "+14159098268"})

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      %{user: user, token: token}
    end

    test "confirms the email with a valid token", %{user: user, token: token} do
      assert {:ok, confirmed_user} = Accounts.confirm_user(token)
      assert confirmed_user.confirmed_at
      assert confirmed_user.confirmed_at != user.confirmed_at
      assert Repo.get!(User, user.id).confirmed_at
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not confirm with invalid token", %{user: user} do
      assert Accounts.confirm_user("oops") == :error
      refute Repo.get!(User, user.id).confirmed_at
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not confirm email if token expired", %{user: user, token: token} do
      {1, nil} =
        Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert Accounts.confirm_user(token) == :error
      refute Repo.get!(User, user.id).confirmed_at
      assert Repo.get_by(UserToken, user_id: user.id)
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
               password_confirmation: ["does not match password"]
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
      assert %{agreed_to_bylaws: ["must be accepted"]} = errors_on(changeset)
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
      today = Date.utc_today()

      assert {:ok, updated_user} = Accounts.remove_board_position(user)
      assert updated_user.board_position == nil

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
end
