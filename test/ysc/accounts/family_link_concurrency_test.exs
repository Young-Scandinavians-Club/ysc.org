defmodule Ysc.Accounts.FamilyLinkConcurrencyTest do
  @moduledoc """
  Concurrency tests for family linking caps.

  Invite acceptance locks the primary user row; admin links must take the same
  lock and re-check caps inside the transaction to avoid exceeding limits.
  """
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures

  alias Ysc.Accounts
  alias Ysc.Accounts.FamilyInvites
  alias Ysc.Accounts.User
  alias Ysc.Repo

  defp create_user_with_lifetime_membership(attrs \\ %{}) do
    user_fixture_fast(attrs)
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at:
        DateTime.truncate(DateTime.utc_now(), :second)
    )
    |> Repo.update!()
  end

  defp count_sub_accounts(primary_user_id) do
    from(u in User, where: u.primary_user_id == ^primary_user_id)
    |> Repo.aggregate(:count, :id)
  end

  defp seed_nine_sub_accounts(primary_user) do
    for i <- 1..9 do
      %User{}
      |> User.sub_account_registration_changeset(
        %{
          email: "sub#{i}_#{System.unique_integer()}@example.com",
          password: "password123456",
          first_name: "Sub",
          last_name: "User#{i}",
          phone_number:
            "+1415555#{String.pad_leading(Integer.to_string(5000 + i), 4, "0")}",
          date_of_birth: ~D[1990-01-01]
        },
        primary_user.id,
        hash_password: true,
        validate_email: true
      )
      |> Repo.insert!()
    end
  end

  describe "admin_link_user_to_family/3 concurrency" do
    test "only one of concurrent admin link and invite acceptance succeeds at the cap",
         %{sandbox_owner: owner} do
      primary = create_user_with_lifetime_membership()
      seed_nine_sub_accounts(primary)
      assert count_sub_accounts(primary.id) == 9

      invite_email = unique_user_email()
      {:ok, invite} = FamilyInvites.create_invite(primary, invite_email)
      invitee = user_fixture(%{email: invite_email})
      admin_target = user_fixture()

      results =
        [
          Task.async(fn ->
            allow_sandbox(self(), owner)
            FamilyInvites.link_existing_user(invite.token, invitee)
          end),
          Task.async(fn ->
            allow_sandbox(self(), owner)

            Accounts.admin_link_user_to_family(
              primary,
              admin_target,
              relationship: :child
            )
          end)
        ]
        |> Task.await_many(10_000)

      successes = Enum.count(results, &match?({:ok, _}, &1))
      assert successes == 1
      assert count_sub_accounts(primary.id) == 10
    end

    test "only one of two concurrent admin links succeeds at the cap",
         %{sandbox_owner: owner} do
      primary = create_user_with_lifetime_membership()
      seed_nine_sub_accounts(primary)
      assert count_sub_accounts(primary.id) == 9

      victim_a = user_fixture()
      victim_b = user_fixture()

      results =
        [victim_a, victim_b]
        |> Enum.map(fn victim ->
          Task.async(fn ->
            allow_sandbox(self(), owner)

            Accounts.admin_link_user_to_family(
              primary,
              victim,
              relationship: :child
            )
          end)
        end)
        |> Task.await_many(10_000)

      successes = Enum.count(results, &match?({:ok, _}, &1))
      assert successes == 1
      assert count_sub_accounts(primary.id) == 10
    end
  end
end
