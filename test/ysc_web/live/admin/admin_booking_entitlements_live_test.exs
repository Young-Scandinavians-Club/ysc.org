defmodule YscWeb.AdminBookingEntitlementsLiveTest do
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Bookings.Entitlements
  alias Money

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

  defp grant_entitlement!(user, admin, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          user_id: user.id,
          issued_by_user_id: admin.id,
          benefit_kind: :fixed_amount_off,
          amount_off: Money.new(:USD, 25)
        },
        attrs
      )

    {:ok, ent} =
      Entitlements.create_entitlement(attrs, send_notification: false)

    ent
  end

  describe "access control" do
    test "redirects unauthenticated users", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/admin/bookings/entitlements")

      assert path =~ "/users/log"
    end

    test "redirects regular members to home", %{conn: conn} do
      member = user_fixture()
      conn = log_in_user(conn, member)

      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/admin/bookings/entitlements")

      assert path == ~p"/"
    end
  end

  describe "deferred outstanding entitlements loading" do
    setup [:create_admin]

    test "replaces loading placeholder with the entitlements table after connect",
         %{
           conn: conn,
           admin: admin
         } do
      member = user_fixture(%{first_name: "Deferred", last_name: "Member"})
      grant_entitlement!(member, admin)

      {:ok, view, _html} = live(conn, ~p"/admin/bookings/entitlements")

      html = render(view)

      refute html =~ "Loading entitlements…"
      assert html =~ "Deferred Member"
      assert has_element?(view, "#grant-entitlement-form-org")
    end

    test "shows empty state after connect when no entitlements match filter", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/bookings/entitlements")

      html = render(view)

      refute html =~ "Loading entitlements…"
      assert html =~ "No outstanding entitlements for this filter."
    end

    test "property filter reloads outstanding entitlements after connect", %{
      conn: conn,
      admin: admin
    } do
      tahoe_member = user_fixture(%{first_name: "Tahoe", last_name: "Holder"})
      clear_member = user_fixture(%{first_name: "Clear", last_name: "Holder"})

      grant_entitlement!(tahoe_member, admin, %{property: :tahoe})
      grant_entitlement!(clear_member, admin, %{property: :clear_lake})

      {:ok, view, _html} =
        live(conn, ~p"/admin/bookings/entitlements?property=tahoe")

      html = render(view)

      assert html =~ "Tahoe Holder"
      refute html =~ "Clear Holder"

      view |> element("a", "Clear Lake") |> render_click()

      html = render(view)

      refute html =~ "Loading entitlements…"
      assert html =~ "Clear Holder"
      refute html =~ "Tahoe Holder"
    end
  end

  describe "grant and revoke benefits" do
    setup [:create_admin]

    test "grants a fixed-amount benefit and lists it in the table", %{
      conn: conn,
      admin: admin
    } do
      member = user_fixture(%{first_name: "Grant", last_name: "Target"})

      {:ok, view, _html} = live(conn, ~p"/admin/bookings/entitlements")

      view
      |> element("#entitlement-grant-user-autocomplete-input")
      |> render_keyup(%{"value" => member.email})

      view
      |> element(
        "button[phx-click='select-entitlement-grant-user'][phx-value-id='#{member.id}']"
      )
      |> render_click()

      view
      |> form("#grant-entitlement-form-org", %{
        "entitlement" => %{
          "benefit_kind" => "fixed_amount_off",
          "amount_off" => "40.00",
          "property" => "tahoe"
        }
      })
      |> render_submit()

      html = render(view)

      assert html =~ "Grant Target"
      assert html =~ "$40.00 off"
      assert length(Entitlements.list_outstanding(property: nil)) == 1

      [ent] = Entitlements.list_outstanding(property: :tahoe)
      assert ent.user_id == member.id
      assert ent.issued_by_user_id == admin.id
      assert Money.equal?(ent.amount_off, Money.new(:USD, "40.00"))
    end

    test "revokes an outstanding benefit from the table", %{
      conn: conn,
      admin: admin
    } do
      member = user_fixture(%{first_name: "Revoke", last_name: "Target"})
      ent = grant_entitlement!(member, admin)

      {:ok, view, _html} = live(conn, ~p"/admin/bookings/entitlements")
      render(view)

      assert has_element?(view, "#revoke-entitlement-org-#{ent.id}")

      view
      |> element("#revoke-entitlement-org-#{ent.id}")
      |> render_click()

      html = render(view)

      refute html =~ "Revoke Target"
      assert Entitlements.list_outstanding() == []
      assert Entitlements.get_entitlement!(ent.id).status == :revoked
    end
  end
end
