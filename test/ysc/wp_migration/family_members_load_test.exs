defmodule Ysc.WpMigration.FamilyMembersLoadTest do
  use Ysc.DataCase, async: true

  import Ecto.Query
  import Ysc.AccountsFixtures

  alias Ysc.Accounts.FamilyMember
  alias Ysc.Repo
  alias Ysc.WpMigration.FamilyMembers
  alias Ysc.WpMigration.FamilyMembersFixtures

  describe "sync_for_user/2" do
    setup do
      %{samples: FamilyMembersFixtures.backup_samples()}
    end

    test "inserts spouse and children from backup sample WP user 41", %{
      samples: samples
    } do
      user = user_fixture()
      sample = Enum.find(samples, &(&1["wp_user_id"] == "41"))

      row =
        FamilyMembersFixtures.application_row_from_meta(
          sample["wp_user_id"],
          sample["meta"]
        )

      assert {:ok, %{inserted: 3, updated: 0, skipped: 0}} =
               FamilyMembers.sync_for_user(user.id, row)

      members =
        FamilyMember
        |> where(user_id: ^user.id)
        |> order_by(asc: :type, asc: :first_name)
        |> Repo.all()

      assert length(members) == 3

      spouse = Enum.find(members, &(&1.type == :spouse))
      assert spouse.first_name == "Andrew"
      assert spouse.last_name == "Napper"

      children =
        members
        |> Enum.filter(&(&1.type == :child))
        |> Enum.sort_by(& &1.first_name)

      assert Enum.map(children, & &1.first_name) == ["Kate", "Olivia"]

      assert Enum.map(children, & &1.birth_date) == [
               ~D[1999-01-01],
               ~D[2009-01-01]
             ]
    end

    test "inserts children-only family from backup sample WP user 31", %{
      samples: samples
    } do
      user = user_fixture()
      sample = Enum.find(samples, &(&1["wp_user_id"] == "31"))

      row =
        FamilyMembersFixtures.application_row_from_meta(
          sample["wp_user_id"],
          sample["meta"]
        )

      assert {:ok, %{inserted: 2, updated: 0, skipped: 0}} =
               FamilyMembers.sync_for_user(user.id, row)

      members = Repo.all(from fm in FamilyMember, where: fm.user_id == ^user.id)
      assert length(members) == 2
      assert Enum.all?(members, &(&1.type == :child))

      names = Enum.map(members, &{&1.first_name, &1.last_name}) |> Enum.sort()
      assert names == [{"Hannah", "Broman"}, {"Lars Erik", "Broman"}]
    end

    test "re-run is idempotent (skipped on unchanged data)", %{samples: samples} do
      user = user_fixture()
      sample = Enum.find(samples, &(&1["wp_user_id"] == "23"))

      row =
        FamilyMembersFixtures.application_row_from_meta(
          sample["wp_user_id"],
          sample["meta"]
        )

      assert {:ok, %{inserted: 1, updated: 0, skipped: 0}} =
               FamilyMembers.sync_for_user(user.id, row)

      assert {:ok, %{inserted: 0, updated: 0, skipped: 1}} =
               FamilyMembers.sync_for_user(user.id, row)

      assert Repo.aggregate(FamilyMember, :count, :id) == 1
    end

    test "updates spouse name on re-run when export data changes", %{
      samples: samples
    } do
      user = user_fixture()
      sample = Enum.find(samples, &(&1["wp_user_id"] == "23"))

      row =
        FamilyMembersFixtures.application_row_from_meta(
          sample["wp_user_id"],
          sample["meta"]
        )

      assert {:ok, %{inserted: 1}} = FamilyMembers.sync_for_user(user.id, row)

      changed =
        row
        |> Map.put("spouse_first_name", "Angela")
        |> Map.put("spouse_last_name", "Smith")

      assert {:ok, %{updated: 1}} =
               FamilyMembers.sync_for_user(user.id, changed)

      spouse = Repo.one!(from fm in FamilyMember, where: fm.user_id == ^user.id)
      assert spouse.last_name == "Smith"
    end

    test "syncs all backup fixture samples end-to-end", %{samples: samples} do
      for sample <- samples do
        user = user_fixture()

        row =
          FamilyMembersFixtures.application_row_from_meta(
            sample["wp_user_id"],
            sample["meta"]
          )

        expected_count =
          if(sample["expected"]["spouse"], do: 1, else: 0) +
            length(sample["expected"]["children"])

        assert {:ok, stats} = FamilyMembers.sync_for_user(user.id, row)
        assert stats.inserted == expected_count

        members =
          Repo.all(from fm in FamilyMember, where: fm.user_id == ^user.id)

        assert length(members) == expected_count
      end
    end
  end
end
