defmodule Ysc.Accounts.FamilyMembersTest do
  # async: false — cache-invalidation tests toggle :process_caches_enabled
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures

  alias Ysc.Accounts
  alias Ysc.Accounts.FamilyMember
  alias Ysc.Accounts.FamilyMembers
  alias Ysc.Repo

  @family_page_preloads [
    :sub_accounts,
    :family_members,
    subscriptions: :subscription_items
  ]

  defp with_process_caches(fun) do
    previous = Application.get_env(:ysc, :process_caches_enabled, false)
    Application.put_env(:ysc, :process_caches_enabled, true)
    Cachex.clear(:ysc_cache)

    try do
      fun.()
    after
      Application.put_env(:ysc, :process_caches_enabled, previous)
      Cachex.clear(:ysc_cache)
    end
  end

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

    test "invalidates profile cache so family page preloads see new members" do
      with_process_caches(fn ->
        user = user_fixture()

        cached = Accounts.get_user!(user.id, @family_page_preloads)
        assert cached.family_members == []

        assert {:ok, _member} =
                 FamilyMembers.upsert_family_member(user, %{
                   "first_name" => "Pelle",
                   "last_name" => "Svans",
                   "relationship" => "child"
                 })

        reloaded = Accounts.get_user!(user.id, @family_page_preloads)

        assert [%{first_name: "Pelle", last_name: "Svans"}] =
                 reloaded.family_members
      end)
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

  describe "list_for_user/1 and find_by_id/2" do
    test "list_for_user returns preloaded members" do
      user = user_fixture()

      member =
        %FamilyMember{}
        |> FamilyMember.family_member_changeset(%{
          first_name: "A",
          last_name: "One",
          type: :child
        })
        |> Ecto.Changeset.put_change(:user_id, user.id)
        |> Repo.insert!()

      user = Repo.preload(user, :family_members)

      assert [found] = FamilyMembers.list_for_user(user)
      assert found.id == member.id
    end

    test "find_by_id returns nil for blank ids" do
      user = user_fixture()
      refute FamilyMembers.find_by_id(user, nil)
      refute FamilyMembers.find_by_id(user, "")
    end

    test "find_by_id matches member id as string" do
      user = user_fixture()

      member =
        %FamilyMember{}
        |> FamilyMember.family_member_changeset(%{
          first_name: "Find",
          last_name: "Me",
          type: :child
        })
        |> Ecto.Changeset.put_change(:user_id, user.id)
        |> Repo.insert!()

      assert %FamilyMember{id: found_id} =
               FamilyMembers.find_by_id(user, to_string(member.id))

      assert found_id == member.id
    end
  end

  describe "record_attrs/1 and validate_params/2" do
    test "record_attrs maps spouse relationship and trims names" do
      attrs =
        FamilyMembers.record_attrs(%{
          "first_name" => "  Pat  ",
          "last_name" => " Lee ",
          "relationship" => "spouse",
          "birth_date" => "2010-01-15"
        })

      assert attrs == %{
               "first_name" => "Pat",
               "last_name" => "Lee",
               "type" => :spouse,
               "birth_date" => "2010-01-15",
               "email" => ""
             }
    end

    test "validate_params rejects future birth dates" do
      user = user_fixture()
      tomorrow = Date.utc_today() |> Date.add(1) |> Date.to_iso8601()

      assert {:error, changeset} =
               FamilyMembers.validate_params(user, %{
                 "first_name" => "Kid",
                 "last_name" => "Future",
                 "relationship" => "child",
                 "birth_date" => tomorrow
               })

      assert "cannot be in the future" in errors_on(changeset).birth_date
    end
  end

  describe "delete_family_member/2" do
    test "deletes member and invalidates profile cache" do
      with_process_caches(fn ->
        user = user_fixture()

        {:ok, member} =
          FamilyMembers.upsert_family_member(user, %{
            "first_name" => "Gone",
            "last_name" => "Soon",
            "relationship" => "child"
          })

        _ = Accounts.get_user!(user.id, @family_page_preloads)

        assert {:ok, _} = FamilyMembers.delete_family_member(user, member)

        reloaded = Accounts.get_user!(user.id, @family_page_preloads)
        assert reloaded.family_members == []
      end)
    end

    test "treats an already-deleted member as a successful deletion" do
      user = user_fixture()

      {:ok, member} =
        FamilyMembers.upsert_family_member(user, %{
          "first_name" => "Already",
          "last_name" => "Gone",
          "relationship" => "child"
        })

      Repo.delete!(member)

      assert {:ok, %FamilyMember{id: deleted_id}} =
               FamilyMembers.delete_family_member(user, member)

      assert deleted_id == member.id
      refute Repo.get(FamilyMember, member.id)
    end

    test "returns unauthorized when member belongs to another user" do
      with_process_caches(fn ->
        owner = user_fixture()
        other = user_fixture()

        {:ok, member} =
          FamilyMembers.upsert_family_member(owner, %{
            "first_name" => "Keep",
            "last_name" => "Me",
            "relationship" => "child"
          })

        # Prime owner's cached profile with the member present.
        cached = Accounts.get_user!(owner.id, @family_page_preloads)
        assert length(cached.family_members) == 1

        assert {:error, :unauthorized} =
                 FamilyMembers.delete_family_member(other, member)

        # Owner cache must not have been invalidated by the unauthorized attempt.
        still_cached = Accounts.get_user!(owner.id, @family_page_preloads)
        assert length(still_cached.family_members) == 1
        assert Repo.get(FamilyMember, member.id)
      end)
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

    test "ignores members deleted after the user's association was loaded" do
      user = user_fixture()

      removed =
        %FamilyMember{}
        |> FamilyMember.family_member_changeset(%{
          first_name: "Concurrently",
          last_name: "Removed",
          type: :child
        })
        |> Ecto.Changeset.put_change(:user_id, user.id)
        |> Repo.insert!()

      user = Repo.preload(user, :family_members)
      Repo.delete!(removed)

      assert :ok = FamilyMembers.delete_removed_members(user, MapSet.new())
    end
  end
end
