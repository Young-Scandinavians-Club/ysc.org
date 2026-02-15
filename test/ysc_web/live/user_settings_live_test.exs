defmodule YscWeb.UserSettingsLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Repo
  alias Ysc.Subscriptions

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
