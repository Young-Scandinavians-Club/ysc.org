defmodule YscWeb.Authorization.EnsureRolePlugTest do
  @moduledoc """
  Tests for the EnsureRolePlug module.
  """
  use YscWeb.ConnCase, async: true

  import Ysc.AccountsFixtures

  alias YscWeb.Authorization.EnsureRolePlug

  describe "call/2" do
    test "allows user with correct role", %{conn: conn} do
      admin = user_fixture(%{role: "admin"})

      conn =
        conn
        |> assign(:current_user, admin)
        |> EnsureRolePlug.call(:admin)

      refute conn.halted
    end

    test "allows user when role is in list", %{conn: conn} do
      admin = user_fixture(%{role: "admin"})

      conn =
        conn
        |> assign(:current_user, admin)
        |> EnsureRolePlug.call([:admin, :member])

      refute conn.halted
    end

    test "halts connection for user without correct role", %{conn: conn} do
      member = user_fixture(%{role: "member"})

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> fetch_flash()
        |> assign(:current_user, member)
        |> EnsureRolePlug.call(:admin)

      assert conn.halted
      assert redirected_to(conn) == "/"
    end

    test "halts connection when no user is present", %{conn: conn} do
      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> fetch_flash()
        |> assign(:current_user, nil)
        |> EnsureRolePlug.call(:admin)

      assert conn.halted
    end
  end

  describe "init/1" do
    test "returns config unchanged" do
      assert EnsureRolePlug.init(:admin) == :admin
      assert EnsureRolePlug.init([:admin, :member]) == [:admin, :member]
    end
  end
end
