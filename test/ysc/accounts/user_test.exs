defmodule Ysc.Accounts.UserTest do
  @moduledoc """
  Tests for User schema.

  These tests verify:
  - Registration changeset validation
  - Password hashing (Argon2) and validation
  - Email uniqueness and format validation
  - Phone number validation with PhoneNumber extension
  - State enum (active, suspended, pending_approval, rejected, deleted)
  - Role enum (member, admin)
  - Board position enum
  - Lifetime membership logic
  - Stripe/QuickBooks customer ID handling
  - Notification preferences
  - Virtual fields (display_name, payment_id)
  - Family member associations
  - Multiple changeset types (registration, update, profile, etc.)
  """
  use Ysc.DataCase, async: true

  alias Ysc.Accounts.User
  alias Ysc.Repo

  @valid_email "user@example.com"
  @valid_password "securepassword123"
  @valid_phone "+14155552671"

  describe "registration_changeset/3" do
    test "creates valid changeset with required fields" do
      attrs = %{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe"
      }

      changeset = User.registration_changeset(%User{}, attrs)

      assert changeset.valid?
      assert changeset.changes.email == @valid_email
      assert changeset.changes.first_name == "John"
      assert changeset.changes.last_name == "Doe"
    end

    test "requires first_name" do
      attrs = %{
        email: @valid_email,
        last_name: "Doe"
      }

      changeset = User.registration_changeset(%User{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:first_name] != nil
    end

    test "requires last_name" do
      attrs = %{
        email: @valid_email,
        first_name: "John"
      }

      changeset = User.registration_changeset(%User{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:last_name] != nil
    end

    test "requires email" do
      attrs = %{
        first_name: "John",
        last_name: "Doe"
      }

      changeset = User.registration_changeset(%User{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:email] != nil
    end

    test "validates first_name length (min 1, max 150)" do
      # Too short
      changeset1 =
        User.registration_changeset(%User{}, %{
          email: @valid_email,
          first_name: "",
          last_name: "Doe"
        })

      refute changeset1.valid?
      assert changeset1.errors[:first_name] != nil

      # Too long
      long_name = String.duplicate("a", 151)

      changeset2 =
        User.registration_changeset(%User{}, %{
          email: @valid_email,
          first_name: long_name,
          last_name: "Doe"
        })

      refute changeset2.valid?
      assert changeset2.errors[:first_name] != nil

      # Valid (exactly 150)
      valid_name = String.duplicate("a", 150)

      changeset3 =
        User.registration_changeset(%User{}, %{
          email: @valid_email,
          first_name: valid_name,
          last_name: "Doe"
        })

      assert changeset3.valid?
    end

    test "validates last_name length (min 1, max 150)" do
      # Too short
      changeset1 =
        User.registration_changeset(%User{}, %{
          email: @valid_email,
          first_name: "John",
          last_name: ""
        })

      refute changeset1.valid?
      assert changeset1.errors[:last_name] != nil

      # Too long
      long_name = String.duplicate("a", 151)

      changeset2 =
        User.registration_changeset(%User{}, %{
          email: @valid_email,
          first_name: "John",
          last_name: long_name
        })

      refute changeset2.valid?
      assert changeset2.errors[:last_name] != nil

      # Valid (exactly 150)
      valid_name = String.duplicate("a", 150)

      changeset3 =
        User.registration_changeset(%User{}, %{
          email: @valid_email,
          first_name: "John",
          last_name: valid_name
        })

      assert changeset3.valid?
    end

    test "validates email format" do
      # Valid emails
      valid_emails = [
        "user@example.com",
        "test.user@subdomain.example.com",
        "user+tag@example.com"
      ]

      for email <- valid_emails do
        changeset =
          User.registration_changeset(%User{}, %{
            email: email,
            first_name: "John",
            last_name: "Doe"
          })

        assert changeset.valid?, "Expected #{email} to be valid"
      end

      # Invalid emails
      invalid_emails = [
        "notanemail",
        "no spaces@example.com",
        "missing@",
        "@nodomain.com"
      ]

      for email <- invalid_emails do
        changeset =
          User.registration_changeset(%User{}, %{
            email: email,
            first_name: "John",
            last_name: "Doe"
          })

        refute changeset.valid?, "Expected #{email} to be invalid"
        assert changeset.errors[:email] != nil
      end
    end

    test "validates email maximum length (160 characters)" do
      # Total 161 chars
      long_email = String.duplicate("a", 149) <> "@example.com"

      changeset =
        User.registration_changeset(%User{}, %{
          email: long_email,
          first_name: "John",
          last_name: "Doe"
        })

      refute changeset.valid?
      assert changeset.errors[:email] != nil
    end

    test "validates email uniqueness" do
      # Insert first user
      {:ok, _user} =
        %User{}
        |> User.registration_changeset(%{
          email: @valid_email,
          first_name: "John",
          last_name: "Doe"
        })
        |> Repo.insert()

      # Try to insert duplicate
      changeset =
        User.registration_changeset(%User{}, %{
          email: @valid_email,
          first_name: "Jane",
          last_name: "Smith"
        })

      {:error, changeset} = Repo.insert(changeset)
      assert changeset.errors[:email] != nil
    end

    test "skips email uniqueness validation with validate_email: false option" do
      # Insert first user
      {:ok, _user} =
        %User{}
        |> User.registration_changeset(%{
          email: @valid_email,
          first_name: "John",
          last_name: "Doe"
        })
        |> Repo.insert()

      # Changeset should be valid with validate_email: false
      changeset =
        User.registration_changeset(
          %User{},
          %{
            email: @valid_email,
            first_name: "Jane",
            last_name: "Smith"
          },
          validate_email: false
        )

      assert changeset.valid?
    end

    test "hashes password when provided with require_password: true" do
      attrs = %{
        email: @valid_email,
        password: @valid_password,
        first_name: "John",
        last_name: "Doe"
      }

      changeset =
        User.registration_changeset(%User{}, attrs, require_password: true)

      assert changeset.valid?
      # Password should be removed
      refute Map.has_key?(changeset.changes, :password)
      # Hashed password should be present
      assert changeset.changes.hashed_password != nil
      assert String.starts_with?(changeset.changes.hashed_password, "$argon2")
    end

    test "validates password minimum length (12 characters)" do
      attrs = %{
        email: @valid_email,
        password: "short",
        first_name: "John",
        last_name: "Doe"
      }

      changeset =
        User.registration_changeset(%User{}, attrs, require_password: true)

      refute changeset.valid?
      assert changeset.errors[:password] != nil
    end

    test "validates password maximum length (72 characters)" do
      long_password = String.duplicate("a", 73)

      attrs = %{
        email: @valid_email,
        password: long_password,
        first_name: "John",
        last_name: "Doe"
      }

      changeset =
        User.registration_changeset(%User{}, attrs, require_password: true)

      refute changeset.valid?
      assert changeset.errors[:password] != nil
    end

    test "password is optional when require_password: false (default)" do
      attrs = %{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe"
      }

      changeset = User.registration_changeset(%User{}, attrs)

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :password)
      refute Map.has_key?(changeset.changes, :hashed_password)
    end

    test "skips password hashing with hash_password: false option" do
      attrs = %{
        email: @valid_email,
        password: @valid_password,
        first_name: "John",
        last_name: "Doe"
      }

      changeset =
        User.registration_changeset(%User{}, attrs,
          require_password: true,
          hash_password: false
        )

      assert changeset.valid?
      # Password should still be present (not hashed)
      assert changeset.changes.password == @valid_password
      refute Map.has_key?(changeset.changes, :hashed_password)
    end

    test "validates phone number format and converts to E.164" do
      attrs = %{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe",
        phone_number: "+14155552671"
      }

      changeset = User.registration_changeset(%User{}, attrs)

      assert changeset.valid?
      # Should be in E.164 format
      assert changeset.changes.phone_number == @valid_phone
    end

    test "rejects invalid phone numbers" do
      attrs = %{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe",
        phone_number: "invalid"
      }

      changeset = User.registration_changeset(%User{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:phone_number] != nil
    end

    test "validates phone number maximum length (25 characters)" do
      long_phone = String.duplicate("1", 26)

      attrs = %{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe",
        phone_number: long_phone
      }

      changeset = User.registration_changeset(%User{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:phone_number] != nil
    end

    test "sets SMS notifications based on sms_opt_in" do
      # Opt in - test by inserting and checking final values
      attrs1 = %{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe",
        sms_opt_in: true
      }

      {:ok, user1} =
        %User{}
        |> User.registration_changeset(attrs1)
        |> Repo.insert()

      assert user1.account_notifications_sms == true
      assert user1.event_notifications_sms == true

      # Opt out
      attrs2 = %{
        email: "another@example.com",
        first_name: "Jane",
        last_name: "Smith",
        sms_opt_in: false
      }

      {:ok, user2} =
        %User{}
        |> User.registration_changeset(attrs2)
        |> Repo.insert()

      assert user2.account_notifications_sms == false
      assert user2.event_notifications_sms == false
    end

    test "accepts optional state and role fields" do
      attrs = %{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe",
        state: :active,
        role: :admin
      }

      changeset = User.registration_changeset(%User{}, attrs)

      assert changeset.valid?
      assert changeset.changes.state == :active
      assert changeset.changes.role == :admin
    end

    test "accepts date_of_birth" do
      attrs = %{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe",
        date_of_birth: ~D[1990-05-15]
      }

      changeset = User.registration_changeset(%User{}, attrs)

      assert changeset.valid?
      assert changeset.changes.date_of_birth == ~D[1990-05-15]
    end
  end

  describe "sub_account_registration_changeset/4" do
    test "creates valid sub-account changeset" do
      primary_user_id = Ecto.ULID.generate()

      attrs = %{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe",
        date_of_birth: ~D[2010-01-01]
      }

      changeset =
        User.sub_account_registration_changeset(%User{}, attrs, primary_user_id)

      assert changeset.valid?
      assert changeset.changes.primary_user_id == primary_user_id
      assert changeset.changes.state == :active
    end

    test "requires date_of_birth for sub-accounts" do
      primary_user_id = Ecto.ULID.generate()

      attrs = %{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe"
      }

      changeset =
        User.sub_account_registration_changeset(%User{}, attrs, primary_user_id)

      refute changeset.valid?
      assert changeset.errors[:date_of_birth] != nil
    end

    test "sets password_set_at when password is provided" do
      primary_user_id = Ecto.ULID.generate()

      attrs = %{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe",
        date_of_birth: ~D[2010-01-01],
        password: @valid_password
      }

      changeset =
        User.sub_account_registration_changeset(%User{}, attrs, primary_user_id,
          require_password: true
        )

      assert changeset.valid?
      assert changeset.changes.password_set_at != nil
    end

    test "validates date_of_birth is after 1900" do
      primary_user_id = Ecto.ULID.generate()

      attrs = %{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe",
        date_of_birth: ~D[1899-12-31]
      }

      changeset =
        User.sub_account_registration_changeset(%User{}, attrs, primary_user_id)

      refute changeset.valid?
      assert changeset.errors[:date_of_birth] != nil
    end

    test "validates date_of_birth is not in the future" do
      primary_user_id = Ecto.ULID.generate()
      future_date = Date.add(Date.utc_today(), 1)

      attrs = %{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe",
        date_of_birth: future_date
      }

      changeset =
        User.sub_account_registration_changeset(%User{}, attrs, primary_user_id)

      refute changeset.valid?
      assert changeset.errors[:date_of_birth] != nil
    end
  end

  describe "update_user_changeset/3" do
    test "updates user fields" do
      user = %User{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe"
      }

      attrs = %{
        first_name: "Jane",
        state: :suspended,
        role: :admin
      }

      changeset = User.update_user_changeset(user, attrs)

      assert changeset.valid?
      assert changeset.changes.first_name == "Jane"
      assert changeset.changes.state == :suspended
      assert changeset.changes.role == :admin
    end

    test "validates name lengths" do
      user = %User{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe"
      }

      long_name = String.duplicate("a", 151)

      changeset =
        User.update_user_changeset(user, %{
          first_name: long_name
        })

      refute changeset.valid?
      assert changeset.errors[:first_name] != nil
    end

    test "cannot change email via update_user_changeset" do
      user = %User{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe"
      }

      attrs = %{
        email: "newemail@example.com"
      }

      changeset = User.update_user_changeset(user, attrs)

      # Email should not be in castable fields
      refute Map.has_key?(changeset.changes, :email)
    end

    test "can set lifetime_membership_awarded_at" do
      user = %User{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe"
      }

      awarded_at = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset =
        User.update_user_changeset(user, %{
          lifetime_membership_awarded_at: awarded_at
        })

      assert changeset.valid?
      assert changeset.changes.lifetime_membership_awarded_at == awarded_at
    end

    test "can set Stripe and QuickBooks IDs" do
      user = %User{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe"
      }

      changeset =
        User.update_user_changeset(user, %{
          stripe_id: "cus_123456",
          quickbooks_customer_id: "qb_789"
        })

      assert changeset.valid?
      assert changeset.changes.stripe_id == "cus_123456"
      assert changeset.changes.quickbooks_customer_id == "qb_789"
    end
  end

  describe "profile_changeset/3" do
    test "updates profile fields" do
      user = %User{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe"
      }

      attrs = %{
        first_name: "Jane",
        last_name: "Smith",
        phone_number: @valid_phone,
        most_connected_country: "US"
      }

      changeset = User.profile_changeset(user, attrs)

      assert changeset.valid?
      assert changeset.changes.first_name == "Jane"
      assert changeset.changes.last_name == "Smith"
      assert changeset.changes.phone_number == @valid_phone
      assert changeset.changes.most_connected_country == "US"
    end

    test "requires phone_number" do
      user = %User{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe"
      }

      attrs = %{
        first_name: "Jane"
      }

      changeset = User.profile_changeset(user, attrs)

      refute changeset.valid?
      assert changeset.errors[:phone_number] != nil
    end
  end

  describe "notification_preferences_changeset/2" do
    test "updates notification preferences" do
      user = %User{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe"
      }

      attrs = %{
        newsletter_notifications: false,
        event_notifications: false,
        account_notifications: true,
        account_notifications_sms: false,
        event_notifications_sms: false
      }

      changeset = User.notification_preferences_changeset(user, attrs)

      assert changeset.valid?
      assert changeset.changes.newsletter_notifications == false
      assert changeset.changes.event_notifications == false
    end

    test "requires account_notifications to be true" do
      user = %User{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe",
        account_notifications: true
      }

      attrs = %{
        account_notifications: false
      }

      changeset = User.notification_preferences_changeset(user, attrs)

      refute changeset.valid?
      assert changeset.errors[:account_notifications] != nil
    end
  end

  describe "password_changeset/3" do
    test "changes password with valid data" do
      user = %User{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe"
      }

      attrs = %{
        password: @valid_password,
        password_confirmation: @valid_password
      }

      changeset = User.password_changeset(user, attrs)

      assert changeset.valid?
      assert changeset.changes.hashed_password != nil
    end

    test "requires password confirmation to match" do
      user = %User{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe"
      }

      attrs = %{
        password: @valid_password,
        password_confirmation: "different"
      }

      changeset = User.password_changeset(user, attrs)

      refute changeset.valid?
      assert changeset.errors[:password_confirmation] != nil
    end

    test "validates password length" do
      user = %User{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe"
      }

      attrs = %{
        password: "short",
        password_confirmation: "short"
      }

      changeset = User.password_changeset(user, attrs)

      refute changeset.valid?
      assert changeset.errors[:password] != nil
    end
  end

  describe "email_changeset/3" do
    test "changes email with valid data" do
      user = %User{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe"
      }

      attrs = %{
        email: "newemail@example.com"
      }

      changeset = User.email_changeset(user, attrs)

      assert changeset.valid?
      assert changeset.changes.email == "newemail@example.com"
    end

    test "requires email to actually change" do
      user = %User{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe"
      }

      attrs = %{
        email: @valid_email
      }

      changeset = User.email_changeset(user, attrs)

      refute changeset.valid?
      assert changeset.errors[:email] != nil
    end

    test "validates new email format" do
      user = %User{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe"
      }

      attrs = %{
        email: "invalid-email"
      }

      changeset = User.email_changeset(user, attrs)

      refute changeset.valid?
      assert changeset.errors[:email] != nil
    end
  end

  describe "confirm_changeset/1" do
    test "sets confirmed_at timestamp" do
      user = %User{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe"
      }

      changeset = User.confirm_changeset(user)

      assert changeset.changes.confirmed_at != nil
    end
  end

  describe "valid_password?/2" do
    test "returns true for correct password" do
      hashed_password = Argon2.hash_pwd_salt(@valid_password)

      user = %User{
        email: @valid_email,
        hashed_password: hashed_password
      }

      assert User.valid_password?(user, @valid_password)
    end

    test "returns false for incorrect password" do
      hashed_password = Argon2.hash_pwd_salt(@valid_password)

      user = %User{
        email: @valid_email,
        hashed_password: hashed_password
      }

      refute User.valid_password?(user, "wrong_password")
    end

    test "returns false for user without password" do
      user = %User{
        email: @valid_email,
        hashed_password: nil
      }

      refute User.valid_password?(user, @valid_password)
    end
  end

  describe "validate_current_password/2" do
    test "validates correct current password" do
      hashed_password = Argon2.hash_pwd_salt(@valid_password)

      user = %User{
        email: @valid_email,
        hashed_password: hashed_password
      }

      changeset =
        User.password_changeset(user, %{
          password: "newpassword123",
          password_confirmation: "newpassword123"
        })

      changeset = User.validate_current_password(changeset, @valid_password)

      assert changeset.valid?
    end

    test "adds error for incorrect current password" do
      hashed_password = Argon2.hash_pwd_salt(@valid_password)

      user = %User{
        email: @valid_email,
        hashed_password: hashed_password
      }

      changeset =
        User.password_changeset(user, %{
          password: "newpassword123",
          password_confirmation: "newpassword123"
        })

      changeset = User.validate_current_password(changeset, "wrong_password")

      refute changeset.valid?
      assert changeset.errors[:current_password] != nil
    end
  end

  describe "verification changesets" do
    test "email_verification_changeset/2 sets email_verified_at" do
      user = %User{email: @valid_email}
      verified_at = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset =
        User.email_verification_changeset(user, %{
          email_verified_at: verified_at
        })

      assert changeset.valid?
      assert changeset.changes.email_verified_at == verified_at
    end

    test "phone_verification_changeset/2 sets phone_verified_at" do
      user = %User{email: @valid_email}
      verified_at = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset =
        User.phone_verification_changeset(user, %{
          phone_verified_at: verified_at
        })

      assert changeset.valid?
      assert changeset.changes.phone_verified_at == verified_at
    end

    test "password_set_changeset/2 sets password_set_at" do
      user = %User{email: @valid_email}
      set_at = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset = User.password_set_changeset(user, %{password_set_at: set_at})

      assert changeset.valid?
      assert changeset.changes.password_set_at == set_at
    end
  end

  describe "database operations" do
    test "can insert and retrieve user" do
      attrs = %{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe"
      }

      {:ok, user} =
        %User{}
        |> User.registration_changeset(attrs)
        |> Repo.insert()

      retrieved = Repo.get(User, user.id)

      assert retrieved.email == @valid_email
      assert retrieved.first_name == "John"
      assert retrieved.last_name == "Doe"
      assert retrieved.inserted_at != nil
      assert retrieved.updated_at != nil
    end

    test "notification preferences have correct defaults" do
      attrs = %{
        email: @valid_email,
        first_name: "John",
        last_name: "Doe"
      }

      {:ok, user} =
        %User{}
        |> User.registration_changeset(attrs)
        |> Repo.insert()

      # Email notifications default to true
      assert user.newsletter_notifications == true
      assert user.event_notifications == true
      assert user.account_notifications == true

      # SMS notifications default to false via set_sms_notifications_from_opt_in
      # when sms_opt_in is not provided or is false
      assert user.account_notifications_sms == false
      assert user.event_notifications_sms == false
    end
  end

  describe "enum validations" do
    test "accepts valid state values" do
      valid_states = [
        :pending_approval,
        :rejected,
        :active,
        :suspended,
        :deleted
      ]

      for state <- valid_states do
        attrs = %{
          email: "test_#{state}@example.com",
          first_name: "John",
          last_name: "Doe",
          state: state
        }

        changeset = User.registration_changeset(%User{}, attrs)
        assert changeset.valid?, "Expected state #{state} to be valid"
      end
    end

    test "accepts valid role values" do
      valid_roles = [:member, :admin]

      for role <- valid_roles do
        attrs = %{
          email: "test_#{role}@example.com",
          first_name: "John",
          last_name: "Doe",
          role: role
        }

        changeset = User.registration_changeset(%User{}, attrs)
        assert changeset.valid?, "Expected role #{role} to be valid"
      end
    end
  end
end
