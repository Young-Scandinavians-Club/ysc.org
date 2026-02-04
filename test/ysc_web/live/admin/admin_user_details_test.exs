defmodule YscWeb.AdminUserDetailsLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Repo
  alias Ysc.Subscriptions

  setup :register_and_log_in_admin

  describe "mount" do
    test "loads user details for viewing", %{conn: conn} do
      user = user_fixture(%{first_name: "John", last_name: "Doe"})

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "John"
      assert html =~ "Doe"
    end

    test "displays user avatar", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert has_element?(view, "[class*='w-24 h-24 rounded-full']")
    end

    test "displays back button", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "Back"
    end

    test "capitalizes user name", %{conn: conn} do
      user = user_fixture(%{first_name: "jane", last_name: "smith"})

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "Jane"
      assert html =~ "Smith"
    end
  end

  describe "navigation tabs" do
    test "displays profile tab", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "Profile"
    end

    test "displays tickets tab", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "Tickets"
    end

    test "displays bookings tab", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "Bookings"
    end

    test "displays application tab", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "Application"
    end

    test "profile tab is active by default", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert has_element?(view, "a.active", "Profile")
    end

    test "can navigate to orders tab", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      {:ok, _view, orders_html} =
        view
        |> element("a[href$='/details/orders']")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/users/#{user.id}/details/orders")

      assert orders_html =~ "Tickets"
    end

    test "can navigate to bookings tab", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      {:ok, _view, bookings_html} =
        view
        |> element("a[href$='/details/bookings']")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/users/#{user.id}/details/bookings")

      assert bookings_html =~ "Bookings"
    end

    test "can navigate to application tab", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      {:ok, _view, application_html} =
        view
        |> element("a[href$='/details/application']")
        |> render_click()
        |> follow_redirect(
          conn,
          ~p"/admin/users/#{user.id}/details/application"
        )

      assert application_html =~ "Application"
    end
  end

  describe "tab highlighting" do
    test "highlights active tab with correct styles", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      # Active tab should have blue styling
      assert html =~ "text-blue-600 border-blue-600"
    end

    test "non-active tabs have hover styles", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      # Non-active tabs should have hover styling
      assert html =~ "hover:text-zinc-600 hover:border-zinc-300"
    end
  end

  describe "back navigation" do
    test "back button links to users list", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert view
             |> element("a", "Back")
             |> render()
             |> then(&(&1 =~ "/admin/users"))
    end
  end

  describe "user avatar" do
    test "displays user avatar with email", %{conn: conn} do
      user = user_fixture(%{email: "test@example.com"})

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      # Avatar component should be rendered
      assert has_element?(view, "[class*='rounded-full']")
    end

    test "displays avatar with correct size", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "w-24 h-24"
    end
  end

  describe "page title" do
    test "displays user name as page title", %{conn: conn} do
      user = user_fixture(%{first_name: "Alice", last_name: "Johnson"})

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "Alice Johnson"
      assert html =~ "text-2xl font-semibold"
    end
  end

  describe "layout" do
    test "uses admin app layout", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      # Should have admin layout elements
      assert html =~ "YSC.org Admin"
    end

    test "displays current user info in navigation", %{
      conn: conn,
      user: admin_user
    } do
      viewed_user = user_fixture()

      {:ok, _view, html} =
        live(conn, ~p"/admin/users/#{viewed_user.id}/details")

      # Admin user info should be displayed
      assert html =~ admin_user.email
    end
  end

  describe "membership tab - create paid membership" do
    test "shows create membership (paid elsewhere) form when user has no subscription and no lifetime",
         %{conn: conn} do
      user = user_fixture()
      # Ensure no lifetime
      user = Repo.get!(Ysc.Accounts.User, user.id)
      assert is_nil(Subscriptions.get_active_subscription(user))

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      {:ok, view, html} =
        view
        |> element("a[href$='/details/membership']")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/users/#{user.id}/details/membership")

      assert html =~ "Create membership (paid elsewhere)"
      assert html =~ "create-paid-membership-form"
      assert has_element?(view, "#create-paid-membership-form")
      assert html =~ "Create membership (paid elsewhere)"
    end

    test "does not show create paid membership form when user has active subscription",
         %{conn: conn} do
      user = user_fixture()
      membership_plans = Application.get_env(:ysc, :membership_plans, [])
      single_plan = Enum.find(membership_plans, &(&1.id == :single))

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 365, :day)
        })

      if single_plan do
        Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_price_id: single_plan.stripe_price_id,
          stripe_product_id: "prod_1",
          stripe_id: "si_#{System.unique_integer()}",
          quantity: 1
        })
      end

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      {:ok, _view, html} =
        view
        |> element("a[href$='/details/membership']")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/users/#{user.id}/details/membership")

      refute html =~ "Create membership (paid elsewhere)"
      assert html =~ "Current Membership"
    end

    test "does not show create paid membership form when user has lifetime membership",
         %{conn: conn} do
      user =
        user_fixture()
        |> Ysc.Accounts.User.update_user_changeset(%{
          lifetime_membership_awarded_at: DateTime.utc_now()
        })
        |> Repo.update!()

      {:ok, _view, html} =
        live(conn, ~p"/admin/users/#{user.id}/details/membership")

      refute html =~ "Create membership (paid elsewhere)"
      assert html =~ "Lifetime Membership"
    end

    test "submitting create paid membership creates subscription and updates UI",
         %{conn: conn} do
      user = user_fixture()
      membership_plans = Application.get_env(:ysc, :membership_plans, [])
      single_plan = Enum.find(membership_plans, &(&1.id == :single))
      assert single_plan != nil

      now_unix = System.system_time(:second)
      fake_stripe_sub = build_fake_stripe_subscription(single_plan, now_unix)
      callback = fn _user, _plan -> {:ok, fake_stripe_sub} end

      try do
        Application.put_env(
          :ysc,
          :create_subscription_paid_out_of_band_stripe_callback,
          callback
        )

        {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

        {:ok, view, _html} =
          view
          |> element("a[href$='/details/membership']")
          |> render_click()
          |> follow_redirect(
            conn,
            ~p"/admin/users/#{user.id}/details/membership"
          )

        assert has_element?(view, "#create-paid-membership-form")

        view
        |> form("#create-paid-membership-form", %{
          "create_paid_membership" => %{"plan_id" => "single"}
        })
        |> render_submit()

        assert render(view) =~ "Membership subscription created"
        assert render(view) =~ "Current Membership"
        assert render(view) =~ single_plan.name
      after
        Application.delete_env(
          :ysc,
          :create_subscription_paid_out_of_band_stripe_callback
        )
      end
    end

    test "shows error when create paid membership fails (callback returns error)",
         %{conn: conn} do
      user = user_fixture()
      callback = fn _user, _plan -> {:error, :stripe_api_error} end

      try do
        Application.put_env(
          :ysc,
          :create_subscription_paid_out_of_band_stripe_callback,
          callback
        )

        {:ok, view, _html} =
          live(conn, ~p"/admin/users/#{user.id}/details/membership")

        view
        |> form("#create-paid-membership-form", %{
          "create_paid_membership" => %{"plan_id" => "single"}
        })
        |> render_submit()

        assert render(view) =~ "Failed to create subscription"
      after
        Application.delete_env(
          :ysc,
          :create_subscription_paid_out_of_band_stripe_callback
        )
      end
    end
  end

  defp build_fake_stripe_subscription(plan, now_unix) do
    period_end = now_unix + 365 * 24 * 60 * 60

    %Stripe.Subscription{
      id: "sub_fake_#{System.unique_integer()}",
      status: "active",
      start_date: now_unix,
      current_period_start: now_unix,
      current_period_end: period_end,
      trial_end: nil,
      ended_at: nil,
      items: %Stripe.List{
        data: [
          %{
            id: "si_fake_#{System.unique_integer()}",
            price: %{id: plan.stripe_price_id, product: "prod_fake"},
            quantity: 1
          }
        ],
        has_more: false,
        object: "list",
        url: "/v1/subscription_items"
      }
    }
  end

  describe "impersonation" do
    test "displays Log in as User button linking to impersonate URL", %{
      conn: conn
    } do
      target = user_fixture(%{first_name: "Alice", last_name: "Target"})

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{target.id}/details")

      assert has_element?(
               view,
               "a[href*='/admin/impersonate/#{target.id}']",
               "Log in as User"
             )
    end

    test "Log in as User button is not shown to non-admin", %{conn: conn} do
      member = user_fixture(%{role: "member"})
      target = user_fixture()
      conn = log_in_user(conn, member)

      # Member cannot access admin user details; they get redirected
      conn = get(conn, ~p"/admin/users/#{target.id}/details")
      assert redirected_to(conn) == ~p"/"
    end
  end

  defp register_and_log_in_admin(%{conn: conn}) do
    user = user_fixture(%{role: :admin})
    %{conn: log_in_user(conn, user), user: user}
  end
end
