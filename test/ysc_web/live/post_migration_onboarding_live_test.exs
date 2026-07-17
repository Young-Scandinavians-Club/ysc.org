defmodule YscWeb.PostMigrationOnboardingLiveTest do
  # Multi-step LiveView onboarding is sensitive to parallel suite load (stepper
  # buttons and family form assigns can race with other async tests).
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Accounts
  alias Ysc.Accounts.FamilyMember
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
      assert has_element?(view, "#onboarding-avatar-section")
      assert render(view) =~ "make sure your details are up to date"
      assert render(view) =~ "Welcome back!"
      assert render(view) =~ "update anything that"
      assert render(view) =~ "out of date"
      assert render(view) =~ "Profile photo"
      assert render(view) =~ "Optional"
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
      {:ok, view, _html} = live(conn, ~p"/onboarding")
      html = render(view)

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

      {:ok, view, _html} = live(conn, ~p"/onboarding")
      html = render(view)

      assert html =~ ">Family</span>"
      refute html =~ "Membership Type"
    end

    test "omits family step when membership application is single", %{
      conn: conn
    } do
      user = user_needing_post_migration_onboarding()
      signup_application_fixture(user, %{membership_type: "single"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/onboarding")
      html = render(view)

      refute html =~ ">Family</span>"
    end

    test "includes membership selection in the stepper when plan cannot be inferred",
         %{conn: conn} do
      user = user_needing_post_migration_onboarding()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/onboarding")
      html = render(view)

      assert html =~ "Membership Type"
    end

    test "lifetime members skip payment but include the family step in the stepper",
         %{conn: conn} do
      user = user_needing_post_migration_onboarding()

      {:ok, user} =
        user
        |> Ecto.Changeset.change(%{
          lifetime_membership_awarded_at:
            DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update()

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/onboarding")
      html = render(view)

      assert has_element?(view, ~s|button[phx-value-step="1"]|)
      assert has_element?(view, ~s|button[phx-value-step="2"]|)
      refute has_element?(view, ~s|button[phx-value-step="3"]|)
      refute html =~ "Membership Type"
      refute html =~ "Renewal Payment"
      assert html =~ ">Family</span>"
    end
  end

  describe "family members step" do
    @onboarding_async_timeout 5_000

    defp family_onboarding_user!(attrs \\ %{}) do
      user = user_needing_post_migration_onboarding(attrs)
      signup_application_fixture(user, %{membership_type: "family"})
      user
    end

    # mount/3 loads signup data via :load_onboarding_data; wait before interacting.
    defp live_onboarding!(conn) do
      {:ok, view, _html} = live(conn, ~p"/onboarding")
      render_async(view, @onboarding_async_timeout)
      refute has_element?(view, "#onboarding-loading")
      assert has_element?(view, "#onboarding-profile-form")
      view
    end

    defp family_step_stepper_index(view) do
      case 0..10
           |> Enum.filter(
             &has_element?(view, ~s|button[phx-value-step="#{&1}"]|)
           ) do
        [] -> flunk("No navigable onboarding steps found in stepper")
        indices -> Enum.max(indices)
      end
    end

    defp go_to_family_step!(view) do
      assert has_element?(view, "#onboarding-profile-form")

      assert has_element?(view, "button", "Family"),
             "expected Family step in onboarding stepper"

      render_click(view, "set-step", %{
        "step" => to_string(family_step_stepper_index(view))
      })

      assert has_element?(view, "#family-member-entries")
    end

    defp fill_family_member_form!(view, idx, overrides \\ %{}) do
      member_params =
        family_member_change_params(idx, overrides)
        |> get_in(["family_members", to_string(idx)])

      view
      |> form("#family-member-form-#{idx}", %{
        "family_members" => %{to_string(idx) => member_params}
      })
      |> render_change()

      assert render(view) =~ member_params["first_name"]
      view
    end

    defp family_member_change_params(idx, overrides) do
      base = %{
        "first_name" => "Family#{idx}",
        "last_name" => "Member",
        "email" => "",
        "birth_date" => "2015-06-01",
        "relationship" => "child"
      }

      %{
        "index" => to_string(idx),
        "family_members" => %{to_string(idx) => Map.merge(base, overrides)}
      }
    end

    test "shows family step for family membership onboarding", %{conn: conn} do
      user = family_onboarding_user!()
      conn = log_in_user(conn, user)

      view = live_onboarding!(conn)
      go_to_family_step!(view)

      assert render(view) =~ "Add Family Members"
      assert has_element?(view, "#family-member-form-0")
    end

    test "shows family step for lifetime membership onboarding", %{conn: conn} do
      user = user_needing_post_migration_onboarding()

      {:ok, user} =
        user
        |> Ecto.Changeset.change(%{
          lifetime_membership_awarded_at:
            DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update()

      conn = log_in_user(conn, user)
      view = live_onboarding!(conn)
      go_to_family_step!(view)

      assert render(view) =~ "Add Family Members"
      assert has_element?(view, "#family-member-form-0")
    end

    test "complete_family_step rejects invalid birth dates", %{conn: conn} do
      user = family_onboarding_user!()
      conn = log_in_user(conn, user)

      view = live_onboarding!(conn)
      go_to_family_step!(view)

      tomorrow =
        Date.utc_today()
        |> Date.add(1)
        |> Date.to_iso8601()

      fill_family_member_form!(view, 0, %{"birth_date" => tomorrow})

      html = render_click(view, "complete_family_step")

      assert html =~ "cannot be in the future"

      assert Accounts.needs_post_migration_onboarding?(
               Accounts.get_user!(user.id)
             )
    end

    test "add_family_member appends another entry form", %{conn: conn} do
      user = family_onboarding_user!()
      conn = log_in_user(conn, user)

      view = live_onboarding!(conn)
      go_to_family_step!(view)

      render_click(view, "add_family_member")

      assert has_element?(view, "#family-member-form-1")
    end

    test "complete_family_step persists members and completes onboarding",
         %{conn: conn} do
      user = family_onboarding_user!()
      conn = log_in_user(conn, user)

      view = live_onboarding!(conn)
      go_to_family_step!(view)
      fill_family_member_form!(view, 0)

      html = render_click(view, "complete_family_step")
      assert html =~ "all set"

      user = Accounts.get_user!(user.id, [:family_members])

      assert length(user.family_members) == 1
      assert user.family_members |> hd() |> Map.get(:first_name) == "Family0"
      refute Accounts.needs_post_migration_onboarding?(user)
    end

    test "complete_family_step without members completes onboarding", %{
      conn: conn
    } do
      user = family_onboarding_user!()
      conn = log_in_user(conn, user)

      view = live_onboarding!(conn)
      go_to_family_step!(view)

      html = render_click(view, "complete_family_step")
      assert html =~ "all set"

      user = Accounts.get_user!(user.id, [:family_members])
      assert user.family_members == []
      refute Accounts.needs_post_migration_onboarding?(user)
    end

    test "remove_family_member deletes a saved member when multiple rows exist",
         %{conn: conn} do
      user = family_onboarding_user!()

      saved =
        %FamilyMember{}
        |> FamilyMember.family_member_changeset(%{
          first_name: "Remove",
          last_name: "Me",
          type: :child
        })
        |> Ecto.Changeset.put_change(:user_id, user.id)
        |> Repo.insert!()

      conn = log_in_user(conn, user)
      view = live_onboarding!(conn)
      go_to_family_step!(view)

      render_click(view, "add_family_member")
      assert has_element?(view, "#family-member-form-1")

      render_click(view, "remove_family_member", %{"index" => "0"})

      refute Repo.get(FamilyMember, saved.id)
      assert has_element?(view, "#family-member-form-0")
      refute has_element?(view, "#family-member-form-1")
    end
  end
end
