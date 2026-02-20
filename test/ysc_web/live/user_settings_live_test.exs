defmodule YscWeb.UserSettingsLiveTest do
  # async: false because tests use Application.put_env for global callback overrides
  # that would race with Ysc.SubscriptionsTest using the same keys
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Accounts.MembershipCache
  alias Ysc.MessagePassingEvents
  alias Ysc.Repo
  alias Ysc.Subscriptions

  describe "membership PubSub real-time updates" do
    setup %{conn: conn} do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)
      %{conn: conn, user: user}
    end

    test "shows info flash when membership is updated for the current user", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/users/membership")

      refute has_element?(view, "#flash-info")

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "memberships:user:#{user.id}",
        {Ysc.Subscriptions,
         %MessagePassingEvents.MembershipUpdated{user_id: user.id}}
      )

      assert has_element?(view, "#flash-info")
    end

    test "reloads membership data and updates the UI on receiving a PubSub event",
         %{
           conn: conn,
           user: user
         } do
      try do
        Application.put_env(
          :ysc,
          :get_scheduled_downgrade_info_callback,
          fn _sub -> nil end
        )

        {:ok, view, _html} = live(conn, ~p"/users/membership")

        refute has_element?(view, "button[phx-click=\"cancel-membership\"]")

        {:ok, _subscription} =
          Subscriptions.create_subscription(%{
            user_id: user.id,
            stripe_id: "sub_pubsub_test_#{System.unique_integer()}",
            stripe_status: "active",
            name: "Membership",
            current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
          })

        MembershipCache.invalidate_user(user.id)

        Phoenix.PubSub.broadcast(
          Ysc.PubSub,
          "memberships:user:#{user.id}",
          {Ysc.Subscriptions,
           %MessagePassingEvents.MembershipUpdated{user_id: user.id}}
        )

        assert has_element?(view, "button[phx-click=\"cancel-membership\"]")
      after
        Application.delete_env(:ysc, :get_scheduled_downgrade_info_callback)
      end
    end

    test "ignores membership updates intended for a different user", %{
      conn: conn
    } do
      other_user = user_fixture(%{state: :active})

      {:ok, view, _html} = live(conn, ~p"/users/membership")

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "memberships:user:#{other_user.id}",
        {Ysc.Subscriptions,
         %MessagePassingEvents.MembershipUpdated{user_id: other_user.id}}
      )

      refute has_element?(view, "#flash-info")
    end
  end

  describe "scheduled downgrade notice" do
    test "displays downgrade scheduled notice when user has scheduled downgrade",
         %{
           conn: conn
         } do
      user = user_fixture(%{state: :active})

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_scheduled_test",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      subscription = Repo.preload(subscription, :subscription_items)
      effective_date = DateTime.add(DateTime.utc_now(), 30, :day)

      callback = fn sub ->
        assert sub.id == subscription.id
        %{target_plan: :single, effective_date: effective_date}
      end

      try do
        Application.put_env(
          :ysc,
          :get_scheduled_downgrade_info_callback,
          callback
        )

        conn = log_in_user(conn, user)

        {:ok, view, _html} = live(conn, ~p"/users/membership")

        # load_settings_data runs on connect - wait for scheduled downgrade notice
        assert view
               |> element("[data-testid=\"scheduled-downgrade-notice\"]")
               |> has_element?(),
               "Expected scheduled downgrade notice to be visible"
      after
        Application.delete_env(:ysc, :get_scheduled_downgrade_info_callback)
      end
    end

    test "does not display downgrade notice when user has no scheduled downgrade",
         %{
           conn: conn
         } do
      user = user_fixture(%{state: :active})

      {:ok, _subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_no_schedule",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      callback = fn _sub -> nil end

      try do
        Application.put_env(
          :ysc,
          :get_scheduled_downgrade_info_callback,
          callback
        )

        conn = log_in_user(conn, user)

        {:ok, _view, html} = live(conn, ~p"/users/membership")

        refute html =~ "Downgrade Scheduled"
      after
        Application.delete_env(:ysc, :get_scheduled_downgrade_info_callback)
      end
    end

    test "cancel downgrade button cancels scheduled downgrade", %{conn: conn} do
      user = user_fixture(%{state: :active})

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_cancel_test",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      subscription = Repo.preload(subscription, :subscription_items)
      effective_date = DateTime.add(DateTime.utc_now(), 30, :day)

      get_info_callback = fn sub ->
        assert sub.id == subscription.id
        %{target_plan: :single, effective_date: effective_date}
      end

      cancel_callback = fn sub ->
        assert sub.id == subscription.id
        {:ok, sub}
      end

      try do
        Application.put_env(
          :ysc,
          :get_scheduled_downgrade_info_callback,
          get_info_callback
        )

        Application.put_env(
          :ysc,
          :cancel_scheduled_downgrade_callback,
          cancel_callback
        )

        conn = log_in_user(conn, user)

        {:ok, view, _html} = live(conn, ~p"/users/membership")

        assert view
               |> element("[data-testid=\"scheduled-downgrade-notice\"]")
               |> has_element?()

        view
        |> element("[data-testid=\"scheduled-downgrade-notice\"] button")
        |> render_click()

        flash = assert_redirect(view, ~p"/users/membership")
        assert flash["info"] =~ "Scheduled downgrade cancelled"
      after
        Application.delete_env(:ysc, :get_scheduled_downgrade_info_callback)
        Application.delete_env(:ysc, :cancel_scheduled_downgrade_callback)
      end
    end
  end
end
