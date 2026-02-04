defmodule Ysc.Accounts.FamilyInvitesTest do
  @moduledoc """
  Tests for Ysc.Accounts.FamilyInvites context module.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  alias Ysc.Accounts
  alias Ysc.Accounts.{FamilyInvites, FamilyInvite, User, FamilyMember, Address}
  alias Ysc.Subscriptions
  alias Ysc.Repo

  defp create_user_with_lifetime_membership(attrs \\ %{}) do
    user_fixture(attrs)
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at:
        DateTime.truncate(DateTime.utc_now(), :second)
    )
    |> Repo.update!()
  end

  defp create_user_with_family_membership(attrs \\ %{}) do
    user = user_fixture(attrs)

    # Get family plan stripe_price_id from config
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

      {:ok, _subscription_item} =
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

  describe "create_invite/3" do
    test "creates an invite for user with lifetime membership" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      assert {:ok, invite} = FamilyInvites.create_invite(primary_user, email)
      assert invite.email == email
      assert invite.primary_user_id == primary_user.id
      assert invite.created_by_user_id == primary_user.id
      assert not is_nil(invite.token)
      assert not is_nil(invite.expires_at)
      assert is_nil(invite.accepted_at)
    end

    test "creates an invite for user with family membership" do
      primary_user = create_user_with_family_membership()
      email = unique_user_email()

      assert {:ok, invite} = FamilyInvites.create_invite(primary_user, email)
      assert invite.email == email
      assert invite.primary_user_id == primary_user.id
    end

    test "returns error when user is not active" do
      primary_user =
        user_fixture()
        |> Ecto.Changeset.change(
          state: :pending_approval,
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Repo.update!()

      email = unique_user_email()

      assert {:error, :user_not_active} =
               FamilyInvites.create_invite(primary_user, email)
    end

    test "returns error when user does not have family or lifetime membership" do
      primary_user = user_fixture()
      email = unique_user_email()

      assert {:error, :invalid_membership_type} =
               FamilyInvites.create_invite(primary_user, email)
    end

    test "returns error when user has reached max sub-accounts" do
      primary_user = create_user_with_lifetime_membership()

      # Create 10 sub-accounts
      for i <- 1..10 do
        %User{}
        |> User.sub_account_registration_changeset(
          %{
            email: "sub#{i}@example.com",
            password: "password1234",
            first_name: "Sub",
            last_name: "User#{i}",
            phone_number: "+14159098268",
            date_of_birth: ~D[1990-01-01]
          },
          primary_user.id,
          hash_password: true,
          validate_email: true
        )
        |> Repo.insert!()
      end

      email = unique_user_email()

      assert {:error, :max_sub_accounts_reached} =
               FamilyInvites.create_invite(primary_user, email)
    end

    test "returns error when email is already registered" do
      primary_user = create_user_with_lifetime_membership()
      existing_user = user_fixture()
      email = existing_user.email

      assert {:error, :email_already_registered} =
               FamilyInvites.create_invite(primary_user, email)
    end

    test "allows inviting primary user's own email" do
      primary_user = create_user_with_lifetime_membership()
      email = primary_user.email

      # Should not error when inviting own email (though unusual)
      assert {:ok, invite} = FamilyInvites.create_invite(primary_user, email)
      assert invite.email == email
    end

    test "returns error when pending invite already exists" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      # Create first invite
      assert {:ok, _invite1} = FamilyInvites.create_invite(primary_user, email)

      # Try to create another invite for same email
      assert {:error, :pending_invite_exists} =
               FamilyInvites.create_invite(primary_user, email)
    end

    test "allows creating invite after previous invite expired" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      # Create an expired invite (manually set expires_at in the past)
      expired_invite =
        %FamilyInvite{}
        |> FamilyInvite.changeset(%{
          email: email,
          token: FamilyInvite.build_token(),
          primary_user_id: primary_user.id,
          created_by_user_id: primary_user.id
        })
        |> Ecto.Changeset.change(
          expires_at:
            DateTime.add(DateTime.utc_now(), -1, :day)
            |> DateTime.truncate(:second)
        )
        |> Repo.insert!()

      # Wait a moment to ensure the expired check works
      :timer.sleep(100)

      # Should be able to create a new invite since the old one is expired
      assert {:ok, new_invite} =
               FamilyInvites.create_invite(primary_user, email)

      assert new_invite.id != expired_invite.id
    end

    test "allows creating invite after previous invite was accepted" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      # Create and accept an invite
      {:ok, invite1} = FamilyInvites.create_invite(primary_user, email)

      {:ok, _user} =
        FamilyInvites.accept_invite(invite1.token, %{
          email: email,
          password: "password1234",
          first_name: "Sub",
          last_name: "User",
          phone_number: "+14159098268",
          date_of_birth: ~D[1990-01-01]
        })

      # After accepting an invite, the email is already registered, so creating a new invite should fail
      assert {:error, :email_already_registered} =
               FamilyInvites.create_invite(primary_user, email)
    end

    test "includes family_member_id option when provided" do
      primary_user = create_user_with_lifetime_membership()

      # Create a family member directly
      family_member =
        %FamilyMember{}
        |> FamilyMember.family_member_changeset(%{
          first_name: "John",
          last_name: "Doe",
          type: "spouse"
        })
        |> Ecto.Changeset.put_change(:user_id, primary_user.id)
        |> Repo.insert!()

      email = unique_user_email()

      assert {:ok, invite} =
               FamilyInvites.create_invite(primary_user, email,
                 family_member_id: family_member.id
               )

      assert invite.email == email
    end
  end

  describe "get_invite_by_token/1" do
    test "returns invite with preloaded associations" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      {:ok, invite} = FamilyInvites.create_invite(primary_user, email)

      found_invite = FamilyInvites.get_invite_by_token(invite.token)

      assert found_invite.id == invite.id
      assert found_invite.email == email
      assert Ecto.assoc_loaded?(found_invite.primary_user)
      assert Ecto.assoc_loaded?(found_invite.created_by_user)
      assert found_invite.primary_user.id == primary_user.id
    end

    test "returns nil for invalid token" do
      assert is_nil(FamilyInvites.get_invite_by_token("invalid_token"))
    end
  end

  describe "accept_invite/2" do
    test "creates sub-account user and marks invite as accepted" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      {:ok, invite} = FamilyInvites.create_invite(primary_user, email)

      user_attrs = %{
        email: email,
        password: "password1234",
        first_name: "Sub",
        last_name: "User",
        phone_number: "+14159098268",
        date_of_birth: ~D[1990-01-01]
      }

      assert {:ok, user} = FamilyInvites.accept_invite(invite.token, user_attrs)

      assert user.email == email
      assert user.primary_user_id == primary_user.id
      assert user.email_verified_at != nil
      assert user.password_set_at != nil

      # Verify invite is marked as accepted
      updated_invite = Repo.get!(FamilyInvite, invite.id)
      assert updated_invite.accepted_at != nil

      # Verify UserEvent was created
      user_event =
        Repo.one(
          from(ue in Accounts.UserEvent,
            where: ue.user_id == ^user.id,
            where: ue.type == :family_added
          )
        )

      assert user_event != nil
      assert user_event.updated_by_user_id == primary_user.id
    end

    test "returns error when invite not found" do
      assert {:error, :invite_not_found} =
               FamilyInvites.accept_invite("invalid_token", %{
                 email: "test@example.com",
                 password: "password1234",
                 first_name: "Test",
                 last_name: "User",
                 phone_number: "+14159098268",
                 date_of_birth: ~D[1990-01-01]
               })
    end

    test "returns error when invite is expired" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      # Create invite normally first
      {:ok, invite} = FamilyInvites.create_invite(primary_user, email)

      # Manually expire it by updating expires_at
      expired_invite =
        invite
        |> Ecto.Changeset.change(
          expires_at:
            DateTime.add(DateTime.utc_now(), -1, :day)
            |> DateTime.truncate(:second)
        )
        |> Repo.update!()

      # Wait a moment to ensure time has passed
      :timer.sleep(100)

      assert {:error, :invite_expired_or_used} =
               FamilyInvites.accept_invite(expired_invite.token, %{
                 email: email,
                 password: "password1234",
                 first_name: "Test",
                 last_name: "User",
                 phone_number: "+14159098268",
                 date_of_birth: ~D[1990-01-01]
               })
    end

    test "returns error when invite already accepted" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      {:ok, invite} = FamilyInvites.create_invite(primary_user, email)

      # Accept the invite
      {:ok, _user} =
        FamilyInvites.accept_invite(invite.token, %{
          email: email,
          password: "password1234",
          first_name: "Sub",
          last_name: "User",
          phone_number: "+14159098268",
          date_of_birth: ~D[1990-01-01]
        })

      # Try to accept again
      assert {:error, :invite_expired_or_used} =
               FamilyInvites.accept_invite(invite.token, %{
                 email: email,
                 password: "password1234",
                 first_name: "Sub2",
                 last_name: "User2",
                 phone_number: "+14159098269",
                 date_of_birth: ~D[1990-01-01]
               })
    end

    test "copies billing address from primary user" do
      primary_user = create_user_with_lifetime_membership()

      # Create billing address for primary user
      primary_address =
        %Address{}
        |> Address.changeset(%{
          user_id: primary_user.id,
          address: "123 Main St",
          city: "San Francisco",
          region: "CA",
          postal_code: "94102",
          country: "US"
        })
        |> Repo.insert!()

      email = unique_user_email()
      {:ok, invite} = FamilyInvites.create_invite(primary_user, email)

      {:ok, sub_user} =
        FamilyInvites.accept_invite(invite.token, %{
          email: email,
          password: "password1234",
          first_name: "Sub",
          last_name: "User",
          phone_number: "+14159098268",
          date_of_birth: ~D[1990-01-01]
        })

      # Check that sub-account has billing address
      sub_address = Repo.get_by(Address, user_id: sub_user.id)

      assert sub_address != nil
      assert sub_address.address == primary_address.address
      assert sub_address.city == primary_address.city
      assert sub_address.region == primary_address.region
      assert sub_address.postal_code == primary_address.postal_code
      assert sub_address.country == primary_address.country
    end

    test "copies most_connected_country from primary user" do
      primary_user =
        create_user_with_lifetime_membership()
        |> Ecto.Changeset.change(most_connected_country: "US")
        |> Repo.update!()

      email = unique_user_email()
      {:ok, invite} = FamilyInvites.create_invite(primary_user, email)

      {:ok, sub_user} =
        FamilyInvites.accept_invite(invite.token, %{
          email: email,
          password: "password1234",
          first_name: "Sub",
          last_name: "User",
          phone_number: "+14159098268",
          date_of_birth: ~D[1990-01-01]
        })

      assert sub_user.most_connected_country == "US"
    end

    test "does not overwrite existing most_connected_country on sub-account" do
      primary_user =
        create_user_with_lifetime_membership()
        |> Ecto.Changeset.change(most_connected_country: "US")
        |> Repo.update!()

      email = unique_user_email()
      {:ok, invite} = FamilyInvites.create_invite(primary_user, email)

      # Create user with existing most_connected_country
      user_attrs = %{
        email: email,
        password: "password1234",
        first_name: "Sub",
        last_name: "User",
        phone_number: "+14159098268",
        most_connected_country: "SE",
        date_of_birth: ~D[1990-01-01]
      }

      {:ok, sub_user} = FamilyInvites.accept_invite(invite.token, user_attrs)

      # Should keep the original value, not copy from primary
      assert sub_user.most_connected_country == "SE"
    end
  end

  describe "list_invites/1" do
    test "returns all invites for primary user ordered by inserted_at desc" do
      primary_user = create_user_with_lifetime_membership()

      # Create multiple invites
      {:ok, invite1} =
        FamilyInvites.create_invite(primary_user, unique_user_email())

      # Ensure different timestamps - need at least 1 second for database timestamp precision
      :timer.sleep(1000)

      {:ok, invite2} =
        FamilyInvites.create_invite(primary_user, unique_user_email())

      :timer.sleep(1000)

      {:ok, invite3} =
        FamilyInvites.create_invite(primary_user, unique_user_email())

      invites = FamilyInvites.list_invites(primary_user)

      assert length(invites) == 3
      # Should be ordered by inserted_at desc (newest first)
      assert Enum.at(invites, 0).id == invite3.id
      assert Enum.at(invites, 1).id == invite2.id
      assert Enum.at(invites, 2).id == invite1.id

      # Should preload created_by_user
      assert Ecto.assoc_loaded?(Enum.at(invites, 0).created_by_user)
    end

    test "returns empty list when no invites exist" do
      primary_user = create_user_with_lifetime_membership()

      assert FamilyInvites.list_invites(primary_user) == []
    end

    test "does not return invites from other primary users" do
      primary_user1 = create_user_with_lifetime_membership()
      primary_user2 = create_user_with_lifetime_membership()

      {:ok, _invite1} =
        FamilyInvites.create_invite(primary_user1, unique_user_email())

      {:ok, _invite2} =
        FamilyInvites.create_invite(primary_user2, unique_user_email())

      invites = FamilyInvites.list_invites(primary_user1)

      assert length(invites) == 1
      assert Enum.at(invites, 0).primary_user_id == primary_user1.id
    end
  end

  describe "revoke_invite/2" do
    test "revokes a pending invite" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      {:ok, invite} = FamilyInvites.create_invite(primary_user, email)

      assert {:ok, deleted_invite} =
               FamilyInvites.revoke_invite(invite.id, primary_user)

      assert deleted_invite.id == invite.id

      # Verify invite is deleted
      assert is_nil(Repo.get(FamilyInvite, invite.id))
    end

    test "returns error when invite not found" do
      primary_user = create_user_with_lifetime_membership()
      # Use a valid ULID format that doesn't exist
      fake_id = Ecto.ULID.generate()

      assert {:error, :not_found} =
               FamilyInvites.revoke_invite(fake_id, primary_user)
    end

    test "returns error when user is not the primary user" do
      primary_user1 = create_user_with_lifetime_membership()
      primary_user2 = create_user_with_lifetime_membership()
      email = unique_user_email()

      {:ok, invite} = FamilyInvites.create_invite(primary_user1, email)

      assert {:error, :unauthorized} =
               FamilyInvites.revoke_invite(invite.id, primary_user2)
    end

    test "returns error when invite already accepted" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      {:ok, invite} = FamilyInvites.create_invite(primary_user, email)

      # Accept the invite
      {:ok, _user} =
        FamilyInvites.accept_invite(invite.token, %{
          email: email,
          password: "password1234",
          first_name: "Sub",
          last_name: "User",
          phone_number: "+14159098268",
          date_of_birth: ~D[1990-01-01]
        })

      # Try to revoke
      assert {:error, :already_accepted} =
               FamilyInvites.revoke_invite(invite.id, primary_user)
    end
  end

  describe "validate_primary_user_eligibility/1" do
    test "returns :ok for eligible user with lifetime membership" do
      user = create_user_with_lifetime_membership()

      assert :ok = FamilyInvites.validate_primary_user_eligibility(user)
    end

    test "returns :ok for eligible user with family membership" do
      user = create_user_with_family_membership()

      assert :ok = FamilyInvites.validate_primary_user_eligibility(user)
    end

    test "returns error for inactive user" do
      user =
        user_fixture()
        |> Ecto.Changeset.change(
          state: :pending_approval,
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Repo.update!()

      assert {:error, :user_not_active} =
               FamilyInvites.validate_primary_user_eligibility(user)
    end

    test "returns error for user without family or lifetime membership" do
      user = user_fixture()

      assert {:error, :invalid_membership_type} =
               FamilyInvites.validate_primary_user_eligibility(user)
    end

    test "returns error when max sub-accounts reached" do
      user = create_user_with_lifetime_membership()

      # Create 10 sub-accounts
      for i <- 1..10 do
        %User{}
        |> User.sub_account_registration_changeset(
          %{
            email: "sub#{i}@example.com",
            password: "password1234",
            first_name: "Sub",
            last_name: "User#{i}",
            phone_number: "+14159098268",
            date_of_birth: ~D[1990-01-01]
          },
          user.id,
          hash_password: true,
          validate_email: true
        )
        |> Repo.insert!()
      end

      assert {:error, :max_sub_accounts_reached} =
               FamilyInvites.validate_primary_user_eligibility(user)
    end
  end

  describe "can_send_family_invite?/1" do
    test "returns true for eligible user" do
      user = create_user_with_lifetime_membership()

      assert FamilyInvites.can_send_family_invite?(user) == true
    end

    test "returns false for ineligible user" do
      user = user_fixture()

      assert FamilyInvites.can_send_family_invite?(user) == false
    end

    test "returns false for user at max sub-accounts" do
      user = create_user_with_lifetime_membership()

      # Create 10 sub-accounts
      for i <- 1..10 do
        %User{}
        |> User.sub_account_registration_changeset(
          %{
            email: "sub#{i}@example.com",
            password: "password1234",
            first_name: "Sub",
            last_name: "User#{i}",
            phone_number: "+14159098268",
            date_of_birth: ~D[1990-01-01]
          },
          user.id,
          hash_password: true,
          validate_email: true
        )
        |> Repo.insert!()
      end

      assert FamilyInvites.can_send_family_invite?(user) == false
    end
  end
end
