defmodule YscWeb.Authorization.EnsureApprovedUserPlugTest do
  use YscWeb.ConnCase, async: true

  alias YscWeb.Authorization.EnsureApprovedUserPlug

  describe "init/1" do
    test "returns the config as-is" do
      config = %{some: "config"}
      assert EnsureApprovedUserPlug.init(config) == config
    end
  end

  describe "approved?/1" do
    test "returns true when user state is active" do
      user = %{state: :active}
      assert EnsureApprovedUserPlug.approved?(user) == true
    end

    test "returns false when user state is pending" do
      user = %{state: :pending}
      assert EnsureApprovedUserPlug.approved?(user) == false
    end

    test "returns false when user state is suspended" do
      user = %{state: :suspended}
      assert EnsureApprovedUserPlug.approved?(user) == false
    end

    test "returns false when user state is any non-active state" do
      user = %{state: :rejected}
      assert EnsureApprovedUserPlug.approved?(user) == false
    end
  end

  describe "call/1" do
    test "allows request when user is approved", %{conn: conn} do
      user = %{state: :active}

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> assign(:current_user, user)

      result_conn = EnsureApprovedUserPlug.call(conn)

      refute result_conn.halted
    end

    test "halts and redirects when user is not approved", %{conn: conn} do
      user = %{state: :pending}

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()
        |> assign(:current_user, user)

      result_conn = EnsureApprovedUserPlug.call(conn)

      assert result_conn.halted
      assert redirected_to(result_conn) == "/pending-review"

      assert Phoenix.Flash.get(result_conn.assigns.flash, :error) ==
               "Your account is pending approval"
    end

    test "halts and redirects when user is suspended", %{conn: conn} do
      user = %{state: :suspended}

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()
        |> assign(:current_user, user)

      result_conn = EnsureApprovedUserPlug.call(conn)

      assert result_conn.halted
      assert redirected_to(result_conn) == "/pending-review"
    end

    test "halts and redirects when user is rejected", %{conn: conn} do
      user = %{state: :rejected}

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()
        |> assign(:current_user, user)

      result_conn = EnsureApprovedUserPlug.call(conn)

      assert result_conn.halted
      assert redirected_to(result_conn) == "/pending-review"
    end
  end
end
