defmodule Ysc.WpMigration.BoardMembersTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Accounts
  alias Ysc.Accounts.User
  alias Ysc.Repo
  alias Ysc.WpMigration.BoardMembers

  test "sync_for_user assigns treasurer to Johan Backman email" do
    user =
      user_fixture(%{
        email: "backman93@gmail.com",
        first_name: "Johan",
        last_name: "Backman"
      })

    assert :ok = BoardMembers.sync_for_user(user)

    updated = Repo.get!(User, user.id)
    assert updated.board_position == :treasurer
    assert String.contains?(updated.board_bio || "", "Berkeley")
  end

  test "sync_for_user matches Gmail dotted export email to undotted account" do
    user =
      user_fixture(%{
        email: "eazholm@gmail.com",
        first_name: "Andreas",
        last_name: "Holm"
      })

    assert :ok = BoardMembers.sync_for_user(user)

    updated = Repo.get!(User, user.id)
    assert updated.board_position == :member_outreach
  end

  test "creates Dave Conroy when missing" do
    refute Accounts.get_user_by_email("daveconroy@me.com")

    assert {:ok, stats} =
             BoardMembers.sync_all(only_emails: ["daveconroy@me.com"])

    assert stats.created == 1
    user = Accounts.get_user_by_email("daveconroy@me.com")
    assert user.first_name == "Dave"
    assert user.last_name == "Conroy"
    assert user.board_position == :clear_lake_cabin_master
  end

  test "sync_all assigns positions for existing roster users" do
    user_fixture(%{
      email: "acbuike@gmail.com",
      first_name: "Anne",
      last_name: "Buike"
    })

    assert {:ok, stats} =
             BoardMembers.sync_all(
               only_emails: ["acbuike@gmail.com", "daveconroy@me.com"]
             )

    assert stats.assigned >= 1
    assert stats.created >= 1
  end
end
