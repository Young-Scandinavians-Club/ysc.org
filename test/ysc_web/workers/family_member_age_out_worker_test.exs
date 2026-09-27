defmodule YscWeb.Workers.FamilyMemberAgeOutWorkerTest do
  @moduledoc """
  Tests for detaching child family members who turn 18.
  """
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures

  alias Ysc.Accounts
  alias Ysc.Accounts.{User, UserEvent}
  alias Ysc.Repo
  alias YscWeb.Emails.FamilyMemberAgedOut
  alias YscWeb.Workers.FamilyMemberAgeOutWorker

  @today ~D[2026-09-26]

  defp link(user, primary, attrs) do
    user
    |> Ecto.Changeset.change(
      Map.merge(
        %{primary_user_id: primary.id, family_relationship: "child"},
        attrs
      )
    )
    |> Repo.update!()
  end

  defp aged_out_email_jobs(user) do
    Repo.all(
      from(j in Oban.Job,
        where: j.args["idempotency_key"] == ^"family_member_aged_out_#{user.id}"
      )
    )
  end

  describe "list_aged_out_family_members/2" do
    setup do
      %{primary: user_fixture(%{first_name: "Astrid"})}
    end

    test "includes a child whose 18th birthday is today", %{primary: primary} do
      child = user_fixture() |> link(primary, %{date_of_birth: ~D[2008-09-26]})

      assert [%User{id: id}] = Accounts.list_aged_out_family_members(@today)
      assert id == child.id
    end

    test "includes a child who turned 18 within the lookback window", %{
      primary: primary
    } do
      child = user_fixture() |> link(primary, %{date_of_birth: ~D[2008-09-20]})

      assert [%User{id: id}] = Accounts.list_aged_out_family_members(@today)
      assert id == child.id
    end

    test "excludes a child who turns 18 tomorrow", %{primary: primary} do
      user_fixture() |> link(primary, %{date_of_birth: ~D[2008-09-27]})

      assert [] = Accounts.list_aged_out_family_members(@today)
    end

    test "excludes adult children older than the lookback window", %{
      primary: primary
    } do
      child = user_fixture() |> link(primary, %{date_of_birth: ~D[2000-01-01]})

      assert [] = Accounts.list_aged_out_family_members(@today)

      assert [%User{id: id}] =
               Accounts.list_aged_out_family_members(@today,
                 lookback_days: 365 * 30
               )

      assert id == child.id
    end

    test "excludes spouses", %{primary: primary} do
      user_fixture()
      |> link(primary, %{
        date_of_birth: ~D[2008-09-26],
        family_relationship: "spouse"
      })

      assert [] = Accounts.list_aged_out_family_members(@today)
    end

    test "excludes users who are not in a family" do
      user_fixture()
      |> Ecto.Changeset.change(%{date_of_birth: ~D[2008-09-26]})
      |> Repo.update!()

      assert [] = Accounts.list_aged_out_family_members(@today)
    end

    test "excludes deleted accounts", %{primary: primary} do
      user_fixture()
      |> link(primary, %{date_of_birth: ~D[2008-09-26], state: :deleted})

      assert [] = Accounts.list_aged_out_family_members(@today)
    end
  end

  describe "detach_aged_out_family_member/1" do
    test "detaches the child, records an event, and schedules the email" do
      primary = user_fixture(%{first_name: "Astrid"})

      child =
        user_fixture(%{first_name: "Freja"})
        |> link(primary, %{date_of_birth: ~D[2008-09-26]})

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, detached} = Accounts.detach_aged_out_family_member(child)
        assert is_nil(detached.primary_user_id)
        assert is_nil(detached.family_relationship)

        assert [job] = aged_out_email_jobs(child)
        assert job.args["template"] == FamilyMemberAgedOut.get_template_name()
        assert job.args["recipient"] == child.email
        assert job.args["params"]["first_name"] == "Freja"
        assert job.args["params"]["primary_user_name"] == "Astrid"
        assert job.args["params"]["membership_url"] =~ "/users/membership"
        assert job.args["text_body"] =~ "your own membership"
      end)

      assert Repo.exists?(
               from(e in UserEvent,
                 where:
                   e.user_id == ^child.id and e.type == :family_removed and
                     e.from == ^primary.id and e.to == "none"
               )
             )
    end

    test "does nothing when the member already left the family" do
      primary = user_fixture()

      child =
        user_fixture() |> link(primary, %{date_of_birth: ~D[2008-09-26]})

      {:ok, _} = Accounts.leave_family_membership(child)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:error, :not_sub_account} =
                 Accounts.detach_aged_out_family_member(child)

        assert [] = aged_out_email_jobs(child)
      end)
    end

    test "returns error for a user who is not a sub-account" do
      assert {:error, :not_sub_account} =
               Accounts.detach_aged_out_family_member(user_fixture())
    end
  end

  describe "perform/1" do
    test "completes with no aged-out members" do
      assert :ok = perform_job(FamilyMemberAgeOutWorker, %{})
    end

    test "detaches a child who turned 18 today and leaves others alone" do
      primary = user_fixture()
      today = DateTime.now!("America/Los_Angeles") |> DateTime.to_date()

      aged_out =
        user_fixture()
        |> link(primary, %{date_of_birth: Date.shift(today, year: -18)})

      minor =
        user_fixture()
        |> link(primary, %{
          date_of_birth: today |> Date.add(1) |> Date.shift(year: -18)
        })

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = perform_job(FamilyMemberAgeOutWorker, %{})
        assert [_job] = aged_out_email_jobs(aged_out)
        assert [] = aged_out_email_jobs(minor)
      end)

      assert is_nil(Repo.get!(User, aged_out.id).primary_user_id)
      assert Repo.get!(User, minor.id).primary_user_id == primary.id
    end

    test "lookback_days arg backfills adult children" do
      primary = user_fixture()

      adult =
        user_fixture() |> link(primary, %{date_of_birth: ~D[2000-01-01]})

      assert :ok = perform_job(FamilyMemberAgeOutWorker, %{})
      assert Repo.get!(User, adult.id).primary_user_id == primary.id

      assert :ok =
               perform_job(FamilyMemberAgeOutWorker, %{
                 "lookback_days" => 365 * 30
               })

      assert is_nil(Repo.get!(User, adult.id).primary_user_id)
    end
  end
end
