defmodule YscWeb.PostMigrationOnboardingLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Repo
  alias Ysc.Subscriptions

  # WP-style user inserted without going through register_user/1 (which marks
  # post-migration onboarding complete). Mirrors Accounts post-migration tests.
  defp user_needing_post_migration_onboarding(attrs \\ %{}) do
    user =
      oauth_user_fixture(Map.merge(%{phone_number: unique_user_phone()}, attrs))

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, user} =
      user
      |> Ecto.Changeset.change(%{
        post_migration_onboarding_completed_at: nil,
        email_verified_at: now
      })
      |> Repo.update()

    user
  end

  describe "mount" do
    test "redirects to home when the user has already completed onboarding", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/onboarding")
      assert path == ~p"/"
    end

    test "redirects when the user is not eligible for post-migration onboarding",
         %{conn: conn} do
      user = user_needing_post_migration_onboarding()

      {:ok, user} =
        user
        |> Ecto.Changeset.change(%{state: :pending_approval})
        |> Repo.update()

      conn = log_in_user(conn, user)

      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/onboarding")
      assert path == ~p"/"
    end

    test "shows the profile step when post-migration onboarding is required", %{
      conn: conn
    } do
      user = user_needing_post_migration_onboarding()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/onboarding")

      assert has_element?(view, "#onboarding-profile-form")
      assert render(view) =~ "make sure your details are up to date"
      assert render(view) =~ "recently moved member accounts"
    end
  end

  describe "profile step" do
    test "validate_profile updates the profile form assign without persisting",
         %{
           conn: conn
         } do
      user = user_needing_post_migration_onboarding()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/onboarding")
      render(view)

      new_first = "OnboardingFirst#{System.unique_integer([:positive])}"

      html =
        render_change(view, "validate_profile", %{
          "user" => %{
            "first_name" => new_first,
            "last_name" => user.last_name,
            "phone_number" => user.phone_number || "",
            "date_of_birth" => "",
            "most_connected_country" => user.most_connected_country || ""
          }
        })

      assert html =~ new_first
    end
  end

  describe "mount plan resolution (preloaded subscriptions)" do
    test "omits membership selection when plan is inferred from a migrated subscription",
         %{conn: conn} do
      user = user_needing_post_migration_onboarding()
      plans = Application.fetch_env!(:ysc, :membership_plans)
      family_plan = Enum.find(plans, &(&1.id == :family))
      assert family_plan, "membership_plans must include family"

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "migrated_#{user.id}",
          stripe_status: "active",
          name: "Migrated Family",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      {:ok, _item} =
        Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_id: "si_migrated_#{System.unique_integer([:positive])}",
          stripe_product_id: "prod_family",
          stripe_price_id: family_plan.stripe_price_id,
          quantity: 1
        })

      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/onboarding")

      refute html =~ "Membership Type"
      refute has_element?(view, "#membership-selection")
      assert html =~ ">Family</span>"
      refute html =~ "Add Family Members"
    end

    test "includes family step when membership application is family", %{
      conn: conn
    } do
      user = user_needing_post_migration_onboarding()
      signup_application_fixture(user, %{membership_type: "family"})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/onboarding")

      assert html =~ ">Family</span>"
      refute html =~ "Membership Type"
    end

    test "omits family step when membership application is single", %{
      conn: conn
    } do
      user = user_needing_post_migration_onboarding()
      signup_application_fixture(user, %{membership_type: "single"})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/onboarding")

      refute html =~ ">Family</span>"
    end

    test "includes membership selection in the stepper when plan cannot be inferred",
         %{conn: conn} do
      user = user_needing_post_migration_onboarding()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/onboarding")

      assert html =~ "Membership Type"
    end

    test "lifetime members skip the payment step in the stepper", %{conn: conn} do
      user = user_needing_post_migration_onboarding()

      {:ok, user} =
        user
        |> Ecto.Changeset.change(%{
          lifetime_membership_awarded_at:
            DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update()

      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/onboarding")

      assert has_element?(view, ~s|button[phx-value-step="1"]|)
      refute has_element?(view, ~s|button[phx-value-step="2"]|)
      refute html =~ "Membership Type"
      refute html =~ ">Family</span>"
      refute html =~ "Add Family Members"
    end
  end
end
