defmodule YscWeb.AuthorizationTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias YscWeb.Authorization

  describe "can?/3" do
    test "evaluates the policy for a user" do
      assert Authorization.can?(
               user_fixture(%{role: :admin}),
               :admin_panel_manage
             )

      refute Authorization.can?(
               user_fixture(%{role: :volunteer}),
               :admin_panel_manage
             )

      assert Authorization.can?(
               user_fixture(%{role: :volunteer}),
               :admin_panel_access
             )
    end

    test "accepts a role atom for staff-versus-admin questions" do
      assert Authorization.can?(:admin, :event_unpublish)
      assert Authorization.can?(:volunteer, :event_publish)
      refute Authorization.can?(:volunteer, :event_unpublish)
      refute Authorization.can?(:member, :admin_panel_access)
    end

    test "role atoms never satisfy ownership rules" do
      refute Authorization.can?(:member, :booking_read, %{user_id: "anyone"})
    end

    test "still honours ownership for a real user" do
      member = user_fixture(%{role: :member})
      assert Authorization.can?(member, :booking_read, %{user_id: member.id})
      refute Authorization.can?(member, :booking_read, %{user_id: "other"})
    end

    test "denies nil, unknown roles and :system" do
      refute Authorization.can?(nil, :admin_panel_access)
      refute Authorization.can?(:host, :admin_panel_access)
      refute Authorization.can?("admin", :admin_panel_access)
      refute Authorization.can?(:system, :admin_panel_access)
    end

    test "denies an action the policy does not define" do
      refute Authorization.can?(:admin, :no_such_action)
    end
  end

  describe "authorize/3" do
    test "returns :ok or {:error, :unauthorized}" do
      assert Authorization.authorize(:admin, :event_cancel) == :ok

      assert Authorization.authorize(:volunteer, :event_cancel) ==
               {:error, :unauthorized}

      assert Authorization.authorize(nil, :event_cancel) ==
               {:error, :unauthorized}
    end

    test ":system is trusted only when passed explicitly" do
      assert Authorization.authorize(:system, :event_cancel) == :ok
    end
  end
end
