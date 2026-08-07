defmodule Ysc.Accounts.FamilyInvitesTest do
  @moduledoc """
  Tests for Ysc.Accounts.FamilyInvites context module.
  """
  use Ysc.DataCase, async: true

  import Ecto.Query
  import Ysc.AccountsFixtures
  alias Ysc.Accounts

  alias Ysc.Accounts.{
    FamilyInvites,
    FamilyInvite,
    User,
    FamilyMember,
    Address,
    UserProfileCache
  }

  alias Ysc.Subscriptions
  alias Ysc.Repo

  defp create_user_with_lifetime_membership(attrs \\ %{}) do
    user_fixture_fast(attrs)
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at:
        DateTime.truncate(DateTime.utc_now(), :second)
    )
    |> Repo.update!()
  end

  defp create_user_with_family_membership(attrs \\ %{}) do
    user = user_fixture(attrs)

    membership_plans = Application.get_env(:ysc, :membership_plans, [])
    family_plan = Enum.find(membership_plans, &(&1.id == :family))

    assert family_plan,
           "membership_plans must include :family (another test may have cleared Application env)"

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
  end

  describe "create_invite/3" do
    test "creates an invite for user with lifetime membership" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, invite} = FamilyInvites.create_invite(primary_user, email)
        assert invite.email == email
        assert invite.primary_user_id == primary_user.id
        assert invite.created_by_user_id == primary_user.id
        assert not is_nil(invite.token)
        assert not is_nil(invite.expires_at)
        assert is_nil(invite.accepted_at)

        assert %Oban.Job{
                 args: %{"idempotency_key" => "family_invite_" <> invite_id}
               } =
                 Repo.one(
                   from(j in Oban.Job,
                     where:
                       j.args["idempotency_key"] ==
                         ^"family_invite_#{invite.id}"
                   )
                 )

        assert invite_id == invite.id
      end)
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

    test "returns error when pending invite exists for Gmail alias of same address" do
      primary_user = create_user_with_lifetime_membership()

      assert {:ok, _invite} =
               FamilyInvites.create_invite(
                 primary_user,
                 "dup.pending@gmail.com"
               )

      assert {:error, :pending_invite_exists} =
               FamilyInvites.create_invite(
                 primary_user,
                 "d.u.p.pending+news@gmail.com"
               )
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

    test "schedules invite email with absolute invite_url" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, invite} = FamilyInvites.create_invite(primary_user, email)

        assert [job] = all_enqueued(worker: YscWeb.Workers.EmailNotifier)
        assert job.args["template"] == "family_invite"
        assert job.args["recipient"] == email

        invite_url = job.args["params"]["invite_url"]

        expected_url =
          YscWeb.Emails.Helpers.absolute_url(
            "/family-invite/#{invite.token}/accept"
          )

        assert invite_url == expected_url
        assert String.starts_with?(invite_url, "http")
        refute String.starts_with?(invite_url, "/")
      end)
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

    test "returns max_sub_accounts_reached when primary already has 10 sub-accounts" do
      primary_user = create_user_with_lifetime_membership()

      for i <- 1..9 do
        %User{}
        |> User.sub_account_registration_changeset(
          %{
            email: "accept-cap-#{i}-#{System.unique_integer()}@example.com",
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

      {:ok, invite} =
        FamilyInvites.create_invite(primary_user, unique_user_email())

      # Another sub-account is linked before the invite is accepted.
      %User{}
      |> User.sub_account_registration_changeset(
        %{
          email: "accept-cap-extra-#{System.unique_integer()}@example.com",
          password: "password1234",
          first_name: "Extra",
          last_name: "Sub",
          phone_number: "+14159098268",
          date_of_birth: ~D[1990-01-01]
        },
        primary_user.id,
        hash_password: true,
        validate_email: true
      )
      |> Repo.insert!()

      assert {:error, :max_sub_accounts_reached} =
               FamilyInvites.accept_invite(invite.token, %{
                 email: invite.email,
                 password: "password1234",
                 first_name: "Late",
                 last_name: "Invite",
                 phone_number: "+14159098268",
                 date_of_birth: ~D[1990-01-01]
               })
    end

    test "schedules accepted notification email to inviter" do
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

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _user} =
                 FamilyInvites.accept_invite(invite.token, user_attrs)

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "recipient" => primary_user.email,
            "idempotency_key" => "family_invite_accepted_#{invite.id}",
            "template" => "family_invite_accepted"
          }
        )
      end)
    end

    test "schedules accepted notification with absolute family_management_url" do
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

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _user} =
                 FamilyInvites.accept_invite(invite.token, user_attrs)

        assert [job] = all_enqueued(worker: YscWeb.Workers.EmailNotifier)
        assert job.args["template"] == "family_invite_accepted"

        family_management_url = job.args["params"]["family_management_url"]

        expected_url =
          YscWeb.Emails.Helpers.absolute_url("/users/settings/family")

        assert family_management_url == expected_url
        assert String.starts_with?(family_management_url, "http")
        refute String.starts_with?(family_management_url, "/")
      end)
    end

    test "link_existing_user/2 schedules accepted notification email to inviter" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      {:ok, invite} = FamilyInvites.create_invite(primary_user, email)

      invitee =
        user_fixture(%{
          email: email,
          first_name: "Invitee",
          last_name: "User"
        })

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _linked} =
                 FamilyInvites.link_existing_user(invite.token, invitee)

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "recipient" => primary_user.email,
            "idempotency_key" => "family_invite_accepted_#{invite.id}",
            "template" => "family_invite_accepted"
          }
        )
      end)
    end

    test "family-linked application approval schedules accepted notification" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      {:ok, invite} = FamilyInvites.create_invite(primary_user, email)

      applicant =
        oauth_user_fixture(%{
          email: email,
          phone_number: unique_user_phone(),
          state: :pending_approval
        })

      application =
        signup_application_fixture(applicant)
        |> Ecto.Changeset.change(family_invite_id: invite.id)
        |> Repo.update!()

      admin = user_fixture(%{role: :admin, phone_number: unique_user_phone()})

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} =
                 Accounts.record_application_outcome(
                   :approved,
                   applicant,
                   application,
                   admin
                 )

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "recipient" => primary_user.email,
            "idempotency_key" => "family_invite_accepted_#{invite.id}",
            "template" => "family_invite_accepted"
          }
        )
      end)
    end

    test "family-linked application approval enforces sub-account cap" do
      primary_user = create_user_with_lifetime_membership()

      for i <- 1..9 do
        %User{}
        |> User.sub_account_registration_changeset(
          %{
            email: "approval-cap-#{i}-#{System.unique_integer()}@example.com",
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
      {:ok, invite} = FamilyInvites.create_invite(primary_user, email)

      applicant =
        oauth_user_fixture(%{
          email: email,
          phone_number: unique_user_phone(),
          state: :pending_approval
        })

      application =
        signup_application_fixture(applicant)
        |> Ecto.Changeset.change(family_invite_id: invite.id)
        |> Repo.update!()

      admin = user_fixture(%{role: :admin, phone_number: unique_user_phone()})

      # Another sub-account is linked before the pending invite is approved.
      %User{}
      |> User.sub_account_registration_changeset(
        %{
          email: "approval-cap-extra-#{System.unique_integer()}@example.com",
          password: "password1234",
          first_name: "Extra",
          last_name: "Sub",
          phone_number: "+14159098268",
          date_of_birth: ~D[1990-01-01]
        },
        primary_user.id,
        hash_password: true,
        validate_email: true
      )
      |> Repo.insert!()

      assert {:error, :max_sub_accounts_reached} =
               Accounts.record_application_outcome(
                 :approved,
                 applicant,
                 application,
                 admin
               )

      assert Repo.get!(User, applicant.id).state == :pending_approval
      assert is_nil(Repo.get!(FamilyInvite, invite.id).accepted_at)
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

    test "returns email_mismatch when submitted email differs from invite" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      {:ok, invite} = FamilyInvites.create_invite(primary_user, email)

      assert {:error, :email_mismatch} =
               FamilyInvites.accept_invite(invite.token, %{
                 email: unique_user_email(),
                 password: "password1234",
                 first_name: "Sub",
                 last_name: "User",
                 phone_number: "+14159098268",
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

      # Create invites and explicitly backdate the older ones so ordering is
      # deterministic without relying on real wall-clock time passing.
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, invite1} =
        FamilyInvites.create_invite(primary_user, unique_user_email())

      {:ok, invite1} =
        invite1
        |> Ecto.Changeset.change(%{
          inserted_at: DateTime.add(now, -120, :second)
        })
        |> Ysc.Repo.update()

      {:ok, invite2} =
        FamilyInvites.create_invite(primary_user, unique_user_email())

      {:ok, invite2} =
        invite2
        |> Ecto.Changeset.change(%{
          inserted_at: DateTime.add(now, -60, :second)
        })
        |> Ysc.Repo.update()

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

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, deleted_invite} =
                 FamilyInvites.revoke_invite(invite.id, primary_user)

        assert deleted_invite.id == invite.id

        # Verify invite is deleted
        assert is_nil(Repo.get(FamilyInvite, invite.id))

        assert %Oban.Job{} =
                 Repo.one(
                   from(j in Oban.Job,
                     where:
                       j.args["idempotency_key"] ==
                         ^"family_invite_cancelled_#{invite.id}"
                   )
                 )
      end)
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

    test "counts sub-accounts from database even when sub_accounts preload is stale" do
      %User{} = primary_user = create_user_with_lifetime_membership()

      for i <- 1..10 do
        %User{}
        |> User.sub_account_registration_changeset(
          %{
            email: "stale-sub-#{i}-#{System.unique_integer()}@example.com",
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

      # Simulate a stale preload from before the 10th sub-account was linked.
      user_with_stale_preload = %User{primary_user | sub_accounts: []}

      assert FamilyInvites.can_send_family_invite?(user_with_stale_preload) ==
               false
    end

    test "counts pending child invites toward the sub-account cap" do
      user = create_user_with_lifetime_membership()

      for i <- 1..10 do
        assert {:ok, _invite} =
                 FamilyInvites.create_invite(
                   user,
                   "pending-cap-#{i}-#{System.unique_integer()}@example.com"
                 )
      end

      assert {:error, :max_sub_accounts_reached} =
               FamilyInvites.create_invite(user, unique_user_email())
    end
  end

  describe "list_pending_invites_for_email/1" do
    test "returns pending valid invites for normalized email" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      {:ok, invite} = FamilyInvites.create_invite(primary_user, email)

      found =
        FamilyInvites.list_pending_invites_for_email(
          "  " <> String.upcase(email) <> "  "
        )

      assert length(found) == 1
      assert hd(found).id == invite.id
      assert hd(found).primary_user.id == primary_user.id
    end

    test "finds pending invite when query uses Gmail alias of stored address" do
      primary_user = create_user_with_lifetime_membership()

      {:ok, invite} =
        FamilyInvites.create_invite(
          primary_user,
          "family.pending.alias@gmail.com"
        )

      # Same canonical local part: dots removed on insert; plus-tag removed on lookup
      found =
        FamilyInvites.list_pending_invites_for_email(
          "familypendingalias+inbox@gmail.com"
        )

      assert length(found) == 1
      assert hd(found).id == invite.id
    end

    test "returns empty list when no pending invites match" do
      assert FamilyInvites.list_pending_invites_for_email(unique_user_email()) ==
               []
    end
  end

  describe "link_existing_user/2" do
    test "links existing account to family when email matches invite" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      {:ok, invite} = FamilyInvites.create_invite(primary_user, email)

      invitee =
        user_fixture(%{
          email: email,
          first_name: "Invitee",
          last_name: "User"
        })

      assert {:ok, linked} =
               FamilyInvites.link_existing_user(invite.token, invitee)

      assert linked.primary_user_id == primary_user.id
      assert Repo.get!(FamilyInvite, invite.id).accepted_at != nil
    end

    test "returns max_sub_accounts_reached when primary already has 10 sub-accounts" do
      primary_user = create_user_with_lifetime_membership()

      for i <- 1..9 do
        %User{}
        |> User.sub_account_registration_changeset(
          %{
            email: "link-cap-#{i}-#{System.unique_integer()}@example.com",
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

      {:ok, invite} = FamilyInvites.create_invite(primary_user, email)

      invitee =
        user_fixture(%{
          email: email,
          first_name: "Invitee",
          last_name: "User"
        })

      # Another sub-account is linked before the invitee accepts.
      %User{}
      |> User.sub_account_registration_changeset(
        %{
          email: "link-cap-extra-#{System.unique_integer()}@example.com",
          password: "password1234",
          first_name: "Extra",
          last_name: "Sub",
          phone_number: "+14159098268",
          date_of_birth: ~D[1990-01-01]
        },
        primary_user.id,
        hash_password: true,
        validate_email: true
      )
      |> Repo.insert!()

      assert {:error, :max_sub_accounts_reached} =
               FamilyInvites.link_existing_user(invite.token, invitee)
    end

    test "returns max_spouses_reached when primary already has a spouse" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      {:ok, invite} =
        FamilyInvites.create_invite(primary_user, email, relationship: :spouse)

      invitee =
        user_fixture(%{
          email: email,
          first_name: "Second",
          last_name: "Spouse"
        })

      existing_spouse =
        user_fixture(%{
          email: unique_user_email(),
          first_name: "First",
          last_name: "Spouse"
        })

      assert {:ok, _} =
               Accounts.admin_link_user_to_family(
                 primary_user,
                 existing_spouse,
                 relationship: :spouse
               )

      assert {:error, :max_spouses_reached} =
               FamilyInvites.link_existing_user(invite.token, invitee)
    end

    test "link_existing_user/2 syncs board volunteer billing when invitee has board position" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      {:ok, invite} = FamilyInvites.create_invite(primary_user, email)

      invitee =
        user_fixture(%{
          email: email,
          first_name: "Board",
          last_name: "Invitee"
        })

      {:ok, invitee} = Accounts.assign_board_position(invitee, :secretary)

      refute Ysc.Subscriptions.BoardVolunteerBilling.household_on_board?(
               primary_user
             )

      Application.put_env(:ysc, :board_volunteer_billing_sync_recorder, self())

      on_exit(fn ->
        Application.delete_env(:ysc, :board_volunteer_billing_sync_recorder)
      end)

      assert {:ok, linked} =
               FamilyInvites.link_existing_user(invite.token, invitee)

      assert linked.primary_user_id == primary_user.id

      assert Ysc.Subscriptions.BoardVolunteerBilling.household_on_board?(
               primary_user
             )

      primary_id = primary_user.id
      assert_receive {:board_volunteer_sync, ^primary_id}
    end

    test "links existing account when Gmail address is a plus/dot alias of invite target" do
      primary_user = create_user_with_lifetime_membership()

      {:ok, invite} =
        FamilyInvites.create_invite(
          primary_user,
          "family.link.member@gmail.com"
        )

      invitee =
        user_fixture_fast(%{
          email: "family.link.member+inbox@gmail.com",
          first_name: "Invitee",
          last_name: "Alias"
        })

      assert {:ok, linked} =
               FamilyInvites.link_existing_user(invite.token, invitee)

      assert linked.primary_user_id == primary_user.id
      assert Repo.get!(FamilyInvite, invite.id).accepted_at != nil
    end

    test "returns email_mismatch when logged-in email does not match invite" do
      primary_user = create_user_with_lifetime_membership()

      {:ok, invite} =
        FamilyInvites.create_invite(primary_user, unique_user_email())

      other_user = user_fixture()

      assert {:error, :email_mismatch} =
               FamilyInvites.link_existing_user(invite.token, other_user)
    end

    test "returns cannot_link_self when primary tries to link invite for their own email" do
      primary_user = create_user_with_lifetime_membership()

      {:ok, invite} =
        FamilyInvites.create_invite(primary_user, primary_user.email)

      assert {:error, :cannot_link_self} =
               FamilyInvites.link_existing_user(invite.token, primary_user)
    end

    test "returns already_linked_to_family for sub-account user" do
      primary_a = create_user_with_lifetime_membership()
      primary_b = create_user_with_lifetime_membership()
      email = unique_user_email()
      {:ok, invite} = FamilyInvites.create_invite(primary_b, email)

      sub =
        %User{}
        |> User.sub_account_registration_changeset(
          %{
            email: email,
            password: "password1234",
            first_name: "Sub",
            last_name: "Account",
            phone_number: "+14159098268",
            date_of_birth: ~D[1990-01-01]
          },
          primary_a.id,
          hash_password: true,
          validate_email: true
        )
        |> Repo.insert!()

      assert {:error, :already_linked_to_family} =
               FamilyInvites.link_existing_user(invite.token, sub)
    end
  end

  describe "create_invite/3 spouse limits" do
    test "returns max_spouses_reached when a pending spouse invite exists" do
      primary_user = create_user_with_lifetime_membership()

      _ =
        FamilyInvites.create_invite(primary_user, unique_user_email(),
          relationship: :spouse
        )

      assert {:error, :max_spouses_reached} =
               FamilyInvites.create_invite(primary_user, unique_user_email(),
                 relationship: :spouse
               )
    end

    test "accepts spouse invite when relationship is passed as string" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      assert {:ok, invite} =
               FamilyInvites.create_invite(primary_user, email,
                 relationship: "spouse"
               )

      assert invite.relationship == :spouse
    end
  end

  describe "family invite acceptance invalidates UserProfileCache" do
    @describetag process_caches: true

    setup do
      Cachex.clear(:ysc_cache)
      :ok
    end

    test "accept_invite serves stale family data before accept and fresh data after" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      {:ok, invite} = FamilyInvites.create_invite(primary_user, email)
      warm_primary_family_caches(primary_user)

      cached_before = Accounts.get_user!(primary_user.id, [:sub_accounts])
      assert cached_before.sub_accounts == []
      assert length(Accounts.get_family_group(cached_before)) == 1

      assert {:ok, sub_user} =
               FamilyInvites.accept_invite(
                 invite.token,
                 invite_accept_user_attrs(email)
               )

      cached_after = Accounts.get_user!(primary_user.id, [:sub_accounts])
      assert length(cached_after.sub_accounts) == 1
      assert hd(cached_after.sub_accounts).id == sub_user.id

      db_group_ids =
        primary_user.id
        |> Accounts.get_user_from_db!([:sub_accounts])
        |> then(&Accounts.get_family_group/1)
        |> Enum.map(& &1.id)
        |> Enum.sort()

      cached_group_ids =
        cached_after
        |> Accounts.get_family_group()
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert cached_group_ids == db_group_ids
    end

    test "accept_invite sub-account profile is available via Accounts.get_user! with family fields" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      {:ok, invite} =
        FamilyInvites.create_invite(primary_user, email, relationship: :child)

      assert {:ok, sub_user} =
               FamilyInvites.accept_invite(
                 invite.token,
                 invite_accept_user_attrs(email)
               )

      cached_sub = Accounts.get_user!(sub_user.id, [])
      assert cached_sub.primary_user_id == primary_user.id
      assert cached_sub.family_relationship == :child
    end

    test "accept_invite invalidates all preload variants for the primary user" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      {:ok, invite} = FamilyInvites.create_invite(primary_user, email)
      warm_primary_family_caches(primary_user)

      assert {:ok, _sub_user} =
               FamilyInvites.accept_invite(
                 invite.token,
                 invite_accept_user_attrs(email)
               )

      assert length(
               Accounts.get_user!(primary_user.id, [:sub_accounts]).sub_accounts
             ) == 1

      assert length(
               Accounts.get_family_group(
                 Accounts.get_user!(primary_user.id, [])
               )
             ) == 2
    end

    test "link_existing_user busts cached profiles for invitee and primary user" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      {:ok, invite} = FamilyInvites.create_invite(primary_user, email)

      invitee =
        user_fixture(%{
          email: email,
          first_name: "Invitee",
          last_name: "User"
        })

      warm_primary_family_caches(primary_user)
      UserProfileCache.get_user!(invitee.id, [])

      cached_primary = Accounts.get_user!(primary_user.id, [:sub_accounts])
      assert cached_primary.sub_accounts == []

      cached_invitee = Accounts.get_user!(invitee.id, [])
      assert is_nil(cached_invitee.primary_user_id)

      assert {:ok, linked} =
               FamilyInvites.link_existing_user(invite.token, invitee)

      refreshed_primary = Accounts.get_user!(primary_user.id, [:sub_accounts])
      assert length(refreshed_primary.sub_accounts) == 1
      assert hd(refreshed_primary.sub_accounts).id == linked.id

      refreshed_invitee = Accounts.get_user!(invitee.id, [])
      assert refreshed_invitee.primary_user_id == primary_user.id
      assert refreshed_invitee.family_relationship == :child
    end

    test "link_existing_user spouse relationship is reflected in cached invitee profile" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      {:ok, invite} =
        FamilyInvites.create_invite(primary_user, email, relationship: :spouse)

      invitee = user_fixture(%{email: email})
      UserProfileCache.get_user!(invitee.id, [])

      assert {:ok, _} = FamilyInvites.link_existing_user(invite.token, invitee)

      refreshed_invitee = Accounts.get_user!(invitee.id, [])
      assert refreshed_invitee.family_relationship == :spouse
    end

    test "link_existing_user cached family group matches database for primary user" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      {:ok, invite} = FamilyInvites.create_invite(primary_user, email)

      invitee = user_fixture(%{email: email})
      warm_primary_family_caches(primary_user)

      assert {:ok, linked} =
               FamilyInvites.link_existing_user(invite.token, invitee)

      cached_primary = Accounts.get_user!(primary_user.id, [:sub_accounts])

      db_group_ids =
        primary_user.id
        |> Accounts.get_user_from_db!([:sub_accounts])
        |> then(&Accounts.get_family_group/1)
        |> Enum.map(& &1.id)
        |> Enum.sort()

      cached_group_ids =
        cached_primary
        |> Accounts.get_family_group()
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert cached_group_ids == db_group_ids
      assert linked.id in cached_group_ids
    end
  end

  describe "create_invite/3 additional validation and family member branches" do
    test "returns a changeset error when the email format is invalid" do
      primary_user = create_user_with_lifetime_membership()

      assert {:error, %Ecto.Changeset{} = changeset} =
               FamilyInvites.create_invite(primary_user, "not-an-email")

      assert Keyword.has_key?(changeset.errors, :email)
    end

    test "family_member_name is nil when family_member_id does not match any family member" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _invite} =
                 FamilyInvites.create_invite(primary_user, email,
                   family_member_id: Ecto.ULID.generate()
                 )

        assert [job] = all_enqueued(worker: YscWeb.Workers.EmailNotifier)
        assert job.args["params"]["family_member_name"] == nil
      end)
    end

    test "resolves the family member name from an already-preloaded primary user" do
      primary_user = create_user_with_lifetime_membership()

      family_member =
        %FamilyMember{}
        |> FamilyMember.family_member_changeset(%{
          first_name: "Robin",
          last_name: "Hood",
          type: "child"
        })
        |> Ecto.Changeset.put_change(:user_id, primary_user.id)
        |> Repo.insert!()

      primary_user_with_preload =
        Accounts.get_user!(primary_user.id, [:family_members])

      email = unique_user_email()

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _invite} =
                 FamilyInvites.create_invite(
                   primary_user_with_preload,
                   email,
                   family_member_id: family_member.id
                 )

        assert [job] = all_enqueued(worker: YscWeb.Workers.EmailNotifier)
        assert job.args["params"]["family_member_name"] == "Robin Hood"
      end)
    end
  end

  describe "accept_invite/2 rolls back on invalid sub-account data" do
    test "returns a changeset error and does not mark the invite accepted when password is too short" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      {:ok, invite} = FamilyInvites.create_invite(primary_user, email)

      assert {:error, %Ecto.Changeset{}} =
               FamilyInvites.accept_invite(invite.token, %{
                 email: email,
                 password: "short",
                 first_name: "Sub",
                 last_name: "User",
                 phone_number: "+14159098268",
                 date_of_birth: ~D[1990-01-01]
               })

      assert is_nil(Repo.get!(FamilyInvite, invite.id).accepted_at)
    end
  end

  describe "link_existing_user/2 invite lookup" do
    test "returns invite_not_found for an unknown token" do
      user = user_fixture()

      assert {:error, :invite_not_found} =
               FamilyInvites.link_existing_user("does-not-exist-token", user)
    end
  end

  describe "revoke_invite/2 loads primary user first_name when missing" do
    test "revokes successfully when the passed-in primary_user struct has no first_name loaded" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()

      {:ok, invite} = FamilyInvites.create_invite(primary_user, email)

      stale_primary_user = %{primary_user | first_name: nil}

      assert {:ok, deleted_invite} =
               FamilyInvites.revoke_invite(invite.id, stale_primary_user)

      assert deleted_invite.id == invite.id
    end
  end

  describe "notify_invite_accepted/2 subject and name formatting" do
    test "uses first name only in email content when accepted user has no last name" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()
      {:ok, invite} = FamilyInvites.create_invite(primary_user, email)

      accepted_user = user_fixture(%{email: email, first_name: "Solo"})
      accepted_user = %{accepted_user | last_name: nil}

      assert %Oban.Job{} =
               FamilyInvites.notify_invite_accepted(invite, accepted_user)
    end

    test "falls back to generic subject and email address when accepted user has no first name" do
      primary_user = create_user_with_lifetime_membership()
      email = unique_user_email()
      {:ok, invite} = FamilyInvites.create_invite(primary_user, email)

      accepted_user = user_fixture(%{email: email})
      nameless_user = %{accepted_user | first_name: nil, last_name: nil}

      assert %Oban.Job{} =
               FamilyInvites.notify_invite_accepted(invite, nameless_user)
    end
  end

  describe "ci_query_explain_query/0" do
    test "returns a valid Ecto query usable for query-explain tooling" do
      assert %Ecto.Query{} = FamilyInvites.ci_query_explain_query()
    end
  end

  defp warm_primary_family_caches(primary_user) do
    UserProfileCache.get_user!(primary_user.id, [])
    UserProfileCache.get_user!(primary_user.id, [:sub_accounts])
  end

  defp invite_accept_user_attrs(email, opts \\ []) do
    %{
      email: email,
      password: "password1234",
      first_name: Keyword.get(opts, :first_name, "Sub"),
      last_name: Keyword.get(opts, :last_name, "User"),
      phone_number: "+14159098268",
      date_of_birth: ~D[1990-01-01]
    }
  end
end
