defmodule Ysc.AccountsTest do
  use Ysc.DataCase

  alias Ysc.Accounts
  alias Ysc.Repo

  import Ysc.AccountsFixtures
  alias Ysc.Accounts.{User, UserToken}

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture(%{phone_number: "+14159098268"})
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
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
    test "updates notification preferences" do
      user = user_fixture(%{phone_number: "+14159098268"})
      attrs = %{newsletter_notifications: false}

      assert {:ok, updated} =
               Accounts.update_notification_preferences(user, attrs)

      assert updated.newsletter_notifications == false
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
end
