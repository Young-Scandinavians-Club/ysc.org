defmodule Ysc.Bookings.CabinMasterTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Bookings.CabinMaster
  alias Ysc.EmailConfig
  alias Ysc.Repo

  describe "get/1" do
    test "returns the tahoe cabin master user when one is assigned" do
      master =
        user_fixture()
        |> Ecto.Changeset.change(%{board_position: :tahoe_cabin_master})
        |> Repo.update!()

      assert %Ysc.Accounts.User{id: id} = CabinMaster.get(:tahoe)
      assert id == master.id
    end

    test "resolves property from binary strings" do
      assert CabinMaster.get("tahoe") == CabinMaster.get(:tahoe)
      assert CabinMaster.get("clear_lake") == CabinMaster.get(:clear_lake)
    end

    test "returns nil for unknown properties" do
      assert CabinMaster.get(:unknown) == nil
      assert CabinMaster.get("not_a_real_property_xyz") == nil
      assert CabinMaster.get(nil) == nil
    end

    test "selects contact columns without password hashes or bios" do
      user_fixture(%{first_name: "Pat", last_name: "Master"})
      |> Ecto.Changeset.change(%{
        board_position: :tahoe_cabin_master,
        board_bio: "must not load this bio"
      })
      |> Repo.update!()

      {master, password_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn -> CabinMaster.get(:tahoe) end,
          pattern: ~r/hashed_password|board_bio/i,
          caller_pids: [self()]
        )

      assert password_cols == 0
      assert master.first_name == "Pat"
      assert master.last_name == "Master"
      assert is_binary(master.email)
      assert is_nil(master.hashed_password)
      assert is_nil(master.board_bio)
    end
  end

  describe "get_active/1" do
    test "returns an active cabin master and skips suspended holders" do
      {:ok, active} =
        Ysc.Accounts.assign_board_position(
          user_fixture(%{first_name: "Active", last_name: "Master"}),
          :clear_lake_cabin_master
        )

      assert %Ysc.Accounts.User{id: id} = CabinMaster.get_active(:clear_lake)
      assert id == active.id

      active
      |> Ecto.Changeset.change(%{state: :suspended})
      |> Repo.update!()

      assert CabinMaster.get_active(:clear_lake) == nil
      assert %Ysc.Accounts.User{id: ^id} = CabinMaster.get(:clear_lake)
    end

    test "selects contact columns without password hashes" do
      Ysc.Accounts.assign_board_position(
        user_fixture(),
        :tahoe_cabin_master
      )

      {master, password_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn -> CabinMaster.get_active(:tahoe) end,
          pattern: ~r/hashed_password|board_bio/i,
          caller_pids: [self()]
        )

      assert password_cols == 0
      assert master.id
      assert is_nil(master.hashed_password)
    end
  end

  describe "email/1" do
    test "returns the property mailbox for known properties" do
      assert CabinMaster.email(:tahoe) == EmailConfig.tahoe_email()
      assert CabinMaster.email("clear_lake") == EmailConfig.clear_lake_email()
    end

    test "returns nil for unknown properties" do
      assert CabinMaster.email(:unknown) == nil
      assert CabinMaster.email("not_a_real_property_xyz") == nil
    end
  end

  describe "contact/1" do
    test "includes formatted name, mailbox, and phone when a user is assigned" do
      user_fixture(%{first_name: "Casey", last_name: "Master"})
      |> Ecto.Changeset.change(%{
        board_position: :clear_lake_cabin_master,
        phone_number: "+14155551234"
      })
      |> Repo.update!()

      contact = CabinMaster.contact(:clear_lake)

      assert contact.name == "Casey Master"
      assert contact.email == EmailConfig.clear_lake_email()
      assert is_binary(contact.phone)
      assert contact.phone =~ "415"
    end

    test "keeps the property mailbox when no cabin master user exists" do
      assert CabinMaster.contact(:tahoe) == %{
               name: nil,
               email: EmailConfig.tahoe_email(),
               phone: nil
             }
    end

    test "returns nil mailbox for unknown properties" do
      assert CabinMaster.contact(:unknown) == %{
               name: nil,
               email: nil,
               phone: nil
             }
    end

    test "contact_from_user does not query users again" do
      user_fixture(%{first_name: "Casey", last_name: "Master"})
      |> Ecto.Changeset.change(%{
        board_position: :clear_lake_cabin_master,
        phone_number: "+14155551234"
      })
      |> Repo.update!()

      master = CabinMaster.get(:clear_lake)

      {contact, user_queries} =
        Ysc.QueryCounter.with_query_counter(
          fn -> CabinMaster.contact_from_user(master, :clear_lake) end,
          pattern: ~r/FROM "users"/i,
          caller_pids: [self()]
        )

      assert user_queries == 0
      assert contact.name == "Casey Master"
      assert contact.email == EmailConfig.clear_lake_email()
    end
  end

  describe "ci_query_explain_query/0" do
    test "returns an Ecto query without executing it" do
      query = CabinMaster.ci_query_explain_query()
      assert %Ecto.Query{} = query
    end

    test "active explain query returns an Ecto query without executing it" do
      query = CabinMaster.ci_query_explain_active_query()
      assert %Ecto.Query{} = query
    end
  end
end
