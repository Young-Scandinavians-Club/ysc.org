defmodule Ysc.Accounts.FamilyMembersTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Accounts.FamilyMember
  alias Ysc.Accounts.FamilyMembers
  alias Ysc.Repo

  describe "upsert_family_member/2" do
    test "inserts a new record when no id is provided" do
      user = user_fixture()

      assert {:ok, member} =
               FamilyMembers.upsert_family_member(user, %{
                 "first_name" => "Jane",
                 "last_name" => "Doe",
                 "relationship" => "child"
               })

      assert member.first_name == "Jane"
      assert member.user_id == user.id
    end

    test "updates an existing record when id matches" do
      user = user_fixture()

      member =
        %FamilyMember{}
        |> FamilyMember.family_member_changeset(%{
          first_name: "Jane",
          last_name: "Doe",
          type: :child
        })
        |> Ecto.Changeset.put_change(:user_id, user.id)
        |> Repo.insert!()

      assert {:ok, updated} =
               FamilyMembers.upsert_family_member(user, %{
                 "id" => to_string(member.id),
                 "first_name" => "Jane",
                 "last_name" => "Smith",
                 "relationship" => "child"
               })

      assert updated.id == member.id
      assert updated.last_name == "Smith"
    end

    test "does not match by name when id is missing" do
      user = user_fixture()

      existing =
        %FamilyMember{}
        |> FamilyMember.family_member_changeset(%{
          first_name: "Jane",
          last_name: "Doe",
          type: :child
        })
        |> Ecto.Changeset.put_change(:user_id, user.id)
        |> Repo.insert!()

      assert {:ok, inserted} =
               FamilyMembers.upsert_family_member(user, %{
                 "first_name" => "Jane",
                 "last_name" => "Doe",
                 "relationship" => "child"
               })

      assert inserted.id != existing.id

      user = Repo.preload(user, :family_members, force: true)
      assert length(user.family_members) == 2
    end
  end

  describe "delete_removed_members/2" do
    test "deletes members not in kept_ids" do
      user = user_fixture()

      kept =
        %FamilyMember{}
        |> FamilyMember.family_member_changeset(%{
          first_name: "Keep",
          last_name: "Me",
          type: :child
        })
        |> Ecto.Changeset.put_change(:user_id, user.id)
        |> Repo.insert!()

      removed =
        %FamilyMember{}
        |> FamilyMember.family_member_changeset(%{
          first_name: "Remove",
          last_name: "Me",
          type: :child
        })
        |> Ecto.Changeset.put_change(:user_id, user.id)
        |> Repo.insert!()

      kept_ids = MapSet.new([to_string(kept.id)])

      FamilyMembers.delete_removed_members(user, kept_ids)

      user = Repo.preload(user, :family_members, force: true)
      assert Enum.map(user.family_members, & &1.id) == [kept.id]
      refute Enum.any?(user.family_members, &(&1.id == removed.id))
    end
  end
end
