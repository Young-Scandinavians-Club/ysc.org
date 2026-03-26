defmodule YscWeb.Authorization.Policy.ChecksTest do
  @moduledoc """
  Direct tests for `YscWeb.Authorization.Policy.Checks` helpers.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias YscWeb.Authorization.Policy.Checks

  describe "own_resource/2" do
    test "returns true when resource user_id matches the user" do
      user = user_fixture()
      assert Checks.own_resource(user, %{user_id: user.id})
    end

    test "returns true when resource primary_user_id matches the user" do
      user = user_fixture()
      assert Checks.own_resource(user, %{primary_user_id: user.id})
    end

    test "returns true when user id equals resource primary_user_id (comparison branch)" do
      user = user_fixture()

      assert Checks.own_resource(user, %{
               primary_user_id: user.id,
               user_id: "other"
             })
    end

    test "returns false when neither user_id nor primary_user_id matches" do
      user = user_fixture()
      other = user_fixture()
      refute Checks.own_resource(user, %{user_id: other.id})
      refute Checks.own_resource(user, %{primary_user_id: other.id})
    end

    test "returns false for non-matching types" do
      user = user_fixture()
      refute Checks.own_resource(user, %{})
      refute Checks.own_resource(user, "not_a_map")
    end
  end

  describe "own_resource/3" do
    test "mirrors own_resource/2 for matching user_id" do
      user = user_fixture()
      assert Checks.own_resource(user, %{user_id: user.id}, %{})
    end

    test "returns false when no field matches" do
      user = user_fixture()
      other = user_fixture()
      refute Checks.own_resource(user, %{user_id: other.id}, %{})
    end
  end

  describe "role/3" do
    test "returns true when user's role matches the required role" do
      admin = user_fixture(%{role: "admin"})
      assert Checks.role(admin, %{}, :admin)
    end

    test "returns false when roles differ" do
      member = user_fixture(%{role: "member"})
      refute Checks.role(member, %{}, :admin)
    end
  end

  describe "can_send_family_invite/2" do
    test "returns false when first argument is not a User" do
      refute Checks.can_send_family_invite(%{}, %{})
    end

    test "delegates to Accounts for a real user" do
      user = user_fixture()
      assert is_boolean(Checks.can_send_family_invite(user, %{}))
    end
  end
end
