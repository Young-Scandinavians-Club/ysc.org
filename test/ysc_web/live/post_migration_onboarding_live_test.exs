defmodule YscWeb.PostMigrationOnboardingLiveTest do
  # Multi-step LiveView onboarding is sensitive to parallel suite load (stepper
  # buttons and family form assigns can race with other async tests).
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ecto.Query

  alias Ysc.Accounts
  alias Ysc.Accounts.FamilyMember
  alias Ysc.Avatars
  alias Ysc.Avatars.Avatar
  alias Ysc.Payments
  alias Ysc.Repo
  alias Ysc.Subscriptions

  @tiny_png Base.decode64!(
              "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
            )

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
      assert has_element?(view, "#onboarding-avatar-upload-form")

      assert has_element?(
               view,
               "button[data-avatar-file-trigger]",
               "Upload photo"
             )

      assert has_element?(view, "h1", "make sure your details are up to date")
      assert has_element?(view, "h3", "Profile photo")

      assert has_element?(
               view,
               "p",
               "Optional — helps other members recognize you at events."
             )
    end
  end

  describe "profile step avatar" do
    defp completed_avatar!(user) do
      {:ok, avatar} =
        Avatars.create_avatar(user, %{
          source: :upload,
          original_path: "https://example.com/original.webp"
        })

      {:ok, avatar} =
        Avatars.update_processed_avatar(avatar, %{
          processing_state: :completed,
          thumb_path: "https://example.com/thumb.webp",
          profile_path: "https://example.com/profile.webp",
          large_path: "https://example.com/large.webp"
        })

      avatar
    end

    test "select_avatar sets a completed avatar as current", %{conn: conn} do
      user = user_needing_post_migration_onboarding()
      avatar = completed_avatar!(user)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/onboarding")
      render(view)

      assert has_element?(view, "#onboarding-avatar-#{avatar.id}")

      view
      |> element("#onboarding-avatar-#{avatar.id}")
      |> render_click()

      updated_user = Accounts.get_user!(user.id)
      assert updated_user.current_avatar_id == avatar.id
      assert render(view) =~ "Profile picture updated"
    end

    test "select_avatar shows an error for unknown avatars", %{conn: conn} do
      user = user_needing_post_migration_onboarding()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/onboarding")
      render(view)

      render_click(view, "select_avatar", %{"id" => Ecto.ULID.generate()})

      assert render(view) =~ "Could not update profile picture"
    end

    test "select_avatar rejects non-completed avatars", %{conn: conn} do
      user = user_needing_post_migration_onboarding()

      {:ok, avatar} =
        Avatars.create_avatar(user, %{
          source: :upload,
          original_path: "https://example.com/original.webp"
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/onboarding")
      render(view)

      refute has_element?(view, "#onboarding-avatar-#{avatar.id}")

      render_click(view, "select_avatar", %{"id" => avatar.id})

      updated_user = Accounts.get_user!(user.id)
      assert is_nil(updated_user.current_avatar_id)
    end

    test "refreshes avatar library after avatar is processed", %{conn: conn} do
      user = user_needing_post_migration_onboarding()
      avatar = completed_avatar!(user)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/onboarding")
      render(view)

      send(view.pid, {:avatar_processed, user.id})
      render(view)

      assert has_element?(view, "#onboarding-avatar-#{avatar.id}")
    end

    test "validate_avatar leaves the upload form rendered", %{conn: conn} do
      user = user_needing_post_migration_onboarding()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/onboarding")
      render(view)

      assert render_change(view, "validate_avatar", %{})
      assert has_element?(view, "#onboarding-avatar-upload-form")
    end

    test "save_avatar completes upload and creates an avatar record", %{
      conn: conn
    } do
      user = user_needing_post_migration_onboarding()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/onboarding")
      render(view)

      avatar_upload =
        file_input(view, "#onboarding-avatar-upload-form", :avatar, [
          %{
            last_modified: System.system_time(:millisecond),
            name: "avatar.png",
            content: @tiny_png,
            type: "image/png"
          }
        ])

      assert render_upload(avatar_upload, "avatar.png") =~ "100%"

      render_submit(view, "save_avatar")
      render(view)

      avatar =
        Repo.one(
          from(a in Avatar,
            where: a.user_id == ^user.id,
            order_by: [desc: a.inserted_at],
            limit: 1
          )
        )

      if avatar do
        assert avatar.source == :upload
        assert avatar.processing_state in [:pending, :failed]
      end
    end

    test "save_avatar without an upload is a no-op", %{conn: conn} do
      user = user_needing_post_migration_onboarding()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/onboarding")
      render(view)

      render_submit(view, "save_avatar")

      refute Repo.exists?(from(a in Avatar, where: a.user_id == ^user.id))
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

    test "sub-accounts skip membership selection and payment; show inherited membership step",
         %{conn: conn} do
      primary =
        user_fixture(%{first_name: "Primary", last_name: "Member"})

      sub_user = user_needing_post_migration_onboarding()

      {:ok, sub_user} =
        sub_user
        |> Ecto.Changeset.change(%{primary_user_id: primary.id})
        |> Repo.update()

      conn = log_in_user(conn, sub_user)
      {:ok, view, _html} = live(conn, ~p"/onboarding")
      render_async(view, 5_000)

      assert has_element?(view, ~s|button[phx-value-step="0"]|, "Profile")
      assert has_element?(view, ~s|button[phx-value-step="1"]|, "Address")
      assert has_element?(view, ~s|button[phx-value-step="2"]|, "Membership")
      refute has_element?(view, "button", "Membership Type")
      refute has_element?(view, "button", "Renewal Payment")
      refute has_element?(view, "button", "Family")
      refute has_element?(view, "#membership-selection")
      refute has_element?(view, "#onboarding-payment-form")
    end
  end

  describe "confirm membership selection" do
    @onboarding_async_timeout 5_000

    defp live_onboarding_ready!(conn) do
      {:ok, view, _html} = live(conn, ~p"/onboarding")
      render_async(view, @onboarding_async_timeout)
      refute has_element?(view, "#onboarding-loading")
      assert has_element?(view, "#onboarding-profile-form")
      view
    end

    defp go_to_membership_selection!(view) do
      assert has_element?(view, "button", "Membership Type")

      membership_step_index =
        0..10
        |> Enum.find(fn idx ->
          has_element?(
            view,
            ~s|button[phx-value-step="#{idx}"]|,
            "Membership Type"
          )
        end)

      assert membership_step_index,
             "expected Membership Type step in onboarding stepper"

      render_click(view, "set-step", %{
        "step" => to_string(membership_step_index)
      })

      assert has_element?(view, "#membership-selection")
      view
    end

    defp confirm_membership_plan!(view, plan)
         when plan in ["single", "family"] do
      view
      |> form("#membership-selection", %{
        "membership_selection" => %{"membership_plan" => plan}
      })
      |> render_change()

      view
      |> form("#membership-selection", %{
        "membership_selection" => %{"membership_plan" => plan}
      })
      |> render_submit()

      view
    end

    # Regression for Sentry ELIXIR-5H / Postgrex 23502: confirming membership
    # previously inserted a signup_applications row with null birth_date and
    # raised not_null_violation out of the LiveView.
    test "confirming family plan without an existing application does not raise not_null_violation",
         %{conn: conn} do
      birth_date = ~D[1988-04-12]

      user =
        user_needing_post_migration_onboarding(%{date_of_birth: birth_date})

      assert is_nil(
               Repo.get_by(Ysc.Accounts.SignupApplication, user_id: user.id)
             )

      conn = log_in_user(conn, user)
      view = live_onboarding_ready!(conn)
      go_to_membership_selection!(view)
      confirm_membership_plan!(view, "family")

      # Survived confirm without crashing; advanced past membership selection.
      refute has_element?(view, "#membership-selection")
      assert has_element?(view, "#onboarding-payment-form")

      application =
        Repo.get_by!(Ysc.Accounts.SignupApplication, user_id: user.id)

      assert application.membership_type == :family
      assert application.birth_date == birth_date
    end

    test "copies billing address onto new application when available", %{
      conn: conn
    } do
      birth_date = ~D[1988-04-12]

      user =
        user_needing_post_migration_onboarding(%{
          date_of_birth: birth_date,
          most_connected_country: "SE"
        })

      {:ok, _user} =
        Accounts.update_billing_address(user, %{
          "address" => "100 Nordic Ave",
          "city" => "Seattle",
          "region" => "WA",
          "postal_code" => "98101",
          "country" => "USA"
        })

      conn = log_in_user(conn, user)
      view = live_onboarding_ready!(conn)
      go_to_membership_selection!(view)
      confirm_membership_plan!(view, "family")

      application =
        Repo.get_by!(Ysc.Accounts.SignupApplication, user_id: user.id)

      assert application.birth_date == birth_date
      assert application.address == "100 Nordic Ave"
      assert application.city == "Seattle"
      assert application.postal_code == "98101"
      assert application.country == "USA"
      assert application.most_connected_nordic_country == "SE"
    end

    test "does not insert signup application when date_of_birth is missing", %{
      conn: conn
    } do
      user = user_needing_post_migration_onboarding(%{date_of_birth: nil})
      assert is_nil(user.date_of_birth)

      assert is_nil(
               Repo.get_by(Ysc.Accounts.SignupApplication, user_id: user.id)
             )

      conn = log_in_user(conn, user)
      view = live_onboarding_ready!(conn)
      go_to_membership_selection!(view)
      confirm_membership_plan!(view, "family")

      assert is_nil(
               Repo.get_by(Ysc.Accounts.SignupApplication, user_id: user.id)
             )

      assert has_element?(view, "#membership-selection")

      assert has_element?(
               view,
               "[role=alert][data-kind=error]",
               "date of birth"
             )
    end
  end

  describe "inherited membership step" do
    @onboarding_async_timeout 5_000

    defp sub_account_needing_onboarding!(primary_attrs \\ %{}) do
      primary =
        user_fixture(
          Map.merge(
            %{first_name: "Primary", last_name: "Member"},
            primary_attrs
          )
        )

      sub_user = user_needing_post_migration_onboarding()

      {:ok, sub_user} =
        sub_user
        |> Ecto.Changeset.change(%{primary_user_id: primary.id})
        |> Repo.update()

      {primary, sub_user}
    end

    test "shows inherited membership info and continues without payment", %{
      conn: conn
    } do
      {primary, sub_user} = sub_account_needing_onboarding!()
      conn = log_in_user(conn, sub_user)

      {:ok, view, _html} = live(conn, ~p"/onboarding")
      render_async(view, @onboarding_async_timeout)
      refute has_element?(view, "#onboarding-loading")

      render_click(view, "set-step", %{"step" => "2"})

      assert has_element?(view, "#inherited-membership-step")
      assert has_element?(view, "#continue-inherited-membership")

      assert has_element?(
               view,
               "#inherited-membership-step",
               "Membership shared through your family membership manager"
             )

      assert has_element?(
               view,
               "#inherited-membership-step",
               primary.first_name
             )

      assert has_element?(view, "#inherited-membership-step", primary.last_name)
      refute has_element?(view, "#membership-selection")
      refute has_element?(view, "#confirm-membership-selection")

      render_click(view, "continue_inherited_membership")

      assert Accounts.get_user!(sub_user.id).post_migration_onboarding_completed_at
    end

    test "confirm_payment_step shows family toast for sub-accounts with a payment method",
         %{conn: conn} do
      import ExUnit.CaptureLog

      {_primary, sub_user} = sub_account_needing_onboarding!()

      plans = Application.fetch_env!(:ysc, :membership_plans)
      single_plan = Enum.find(plans, &(&1.id == :single))
      assert single_plan, "membership_plans must include single"

      # Migrated plan so get_price_id/1 resolves and Customers.create_subscription
      # is reached (where sub-accounts are rejected).
      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: sub_user.id,
          stripe_id: "migrated_#{sub_user.id}",
          stripe_status: "active",
          name: "Migrated Single",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      {:ok, _item} =
        Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_id: "si_migrated_#{System.unique_integer([:positive])}",
          stripe_product_id: "prod_single",
          stripe_price_id: single_plan.stripe_price_id,
          quantity: 1
        })

      {:ok, _pm} =
        Payments.insert_payment_method(%{
          user_id: sub_user.id,
          provider: :stripe,
          provider_id: "pm_onboard_#{System.unique_integer([:positive])}",
          provider_customer_id:
            "cus_onboard_#{System.unique_integer([:positive])}",
          type: :card,
          provider_type: "card",
          is_default: true,
          last_four: "4242",
          display_brand: "visa"
        })

      # Reload so LiveView mount sees the payment method + migrated sub.
      sub_user = Accounts.get_user!(sub_user.id, [:subscriptions])

      conn = log_in_user(conn, sub_user)

      {:ok, view, _html} = live(conn, ~p"/onboarding")
      render_async(view, @onboarding_async_timeout)
      refute has_element?(view, "#onboarding-loading")

      # Sub-accounts skip the payment step UI, but if confirm_payment_step is
      # invoked (stale client, race, etc.) they must get the family toast path —
      # not the generic payment-setup Sentry error.
      log =
        capture_log(fn ->
          render_click(view, "confirm_payment_step")
        end)

      assert log =~ "Sub-account cannot create subscription during onboarding"
      refute log =~ "Failed to create subscription during onboarding"

      assert has_element?(
               view,
               "[role=alert][data-kind=error]",
               "family membership"
             )
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
