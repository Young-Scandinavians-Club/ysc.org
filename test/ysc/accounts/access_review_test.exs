defmodule Ysc.Accounts.AccessReviewTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Accounts.{AccessReview, AuthEvent}

  describe "list_privileged_users/0" do
    test "returns non-deleted admins and volunteers ordered by role then name" do
      admin =
        user_fixture(%{
          role: :admin,
          board_position: :president,
          first_name: "Zelda",
          last_name: "Admin"
        })

      volunteer =
        user_fixture(%{role: :volunteer, first_name: "Vic", last_name: "Vol"})

      suspended_admin =
        user_fixture(%{
          role: :admin,
          state: :suspended,
          first_name: "Anna",
          last_name: "Admin"
        })

      _member = user_fixture(%{role: :member})
      _deleted_admin = user_fixture(%{role: :admin, state: :deleted})

      ids = Enum.map(AccessReview.list_privileged_users(), & &1.id)

      assert ids == [suspended_admin.id, admin.id, volunteer.id]
    end

    test "includes the most recent successful sign-in" do
      admin = user_fixture(%{role: :admin})
      never_signed_in = user_fixture(%{role: :volunteer})

      older = ~U[2026-01-10 12:00:00Z]
      newer = ~U[2026-02-20 08:30:00Z]

      for inserted_at <- [older, newer] do
        admin
        |> AuthEvent.login_success_changeset(%{ip_address: "203.0.113.1"})
        |> Ecto.Changeset.put_change(:inserted_at, inserted_at)
        |> Repo.insert!()
      end

      by_id = Map.new(AccessReview.list_privileged_users(), &{&1.id, &1})

      assert by_id[admin.id].last_sign_in_at == newer
      assert by_id[never_signed_in.id].last_sign_in_at == nil
    end

    test "does not treat failed logins as last_sign_in_at" do
      admin = user_fixture(%{role: :admin})
      failure_only = user_fixture(%{role: :volunteer})

      success_at = ~U[2026-01-10 12:00:00Z]
      later_failure_at = ~U[2026-03-01 08:00:00Z]

      admin
      |> AuthEvent.login_success_changeset(%{ip_address: "203.0.113.1"})
      |> Ecto.Changeset.put_change(:inserted_at, success_at)
      |> Repo.insert!()

      for {user, inserted_at} <- [
            {admin, later_failure_at},
            {failure_only, later_failure_at}
          ] do
        AuthEvent.login_failure_changeset(%{
          user_id: user.id,
          email_attempted: user.email,
          failure_reason: "invalid_credentials",
          ip_address: "203.0.113.2"
        })
        |> Ecto.Changeset.put_change(:inserted_at, inserted_at)
        |> Repo.insert!()
      end

      by_id = Map.new(AccessReview.list_privileged_users(), &{&1.id, &1})

      assert by_id[admin.id].last_sign_in_at == success_at
      assert by_id[failure_only.id].last_sign_in_at == nil
    end
  end
end
