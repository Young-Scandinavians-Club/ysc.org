defmodule Ysc.Subscriptions.BoardVolunteerBillingTest do
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures
  import Mox
  import ExUnit.CaptureLog

  alias Ysc.Subscriptions
  alias Ysc.Subscriptions.BoardVolunteerBilling
  alias Ysc.Subscriptions.Subscription
  alias Ysc.Subscriptions.SubscriptionItem
  alias Ysc.Test.EnvHelper

  describe "grace_resume_at_unix_from/1" do
    test "shifts six calendar months and returns unix timestamp" do
      from = ~U[2025-01-15 14:30:45Z]

      unix = BoardVolunteerBilling.grace_resume_at_unix_from(from)
      expected_dt = from |> Timex.shift(months: 6) |> DateTime.truncate(:second)
      assert unix == DateTime.to_unix(expected_dt)
    end

    test "January 31 plus six months yields July 31" do
      from = ~U[2025-01-31 08:00:00Z]
      unix = BoardVolunteerBilling.grace_resume_at_unix_from(from)
      back = DateTime.from_unix!(unix, :second)
      assert back.year == 2025
      assert back.month == 7
      assert back.day == 31
    end
  end

  describe "membership_subscription_for_pause?/1" do
    setup do
      single_price =
        :ysc
        |> Application.fetch_env!(:membership_plans)
        |> Enum.find(&(&1.id == :single))
        |> Map.fetch!(:stripe_price_id)

      %{membership_price_id: single_price}
    end

    test "accepts active subscription with configured membership price", %{
      membership_price_id: price_id
    } do
      sub = %Subscription{
        stripe_id: "sub_active_membership",
        stripe_status: "active",
        subscription_items: [
          %SubscriptionItem{stripe_price_id: price_id}
        ]
      }

      assert BoardVolunteerBilling.membership_subscription_for_pause?(sub)
    end

    test "accepts trialing subscription", %{membership_price_id: price_id} do
      sub = %Subscription{
        stripe_id: "sub_trial",
        stripe_status: "trialing",
        subscription_items: [
          %SubscriptionItem{stripe_price_id: price_id}
        ]
      }

      assert BoardVolunteerBilling.membership_subscription_for_pause?(sub)
    end

    test "rejects migrated placeholder stripe id", %{
      membership_price_id: price_id
    } do
      sub = %Subscription{
        stripe_id: "migrated_sub_123",
        stripe_status: "active",
        subscription_items: [
          %SubscriptionItem{stripe_price_id: price_id}
        ]
      }

      refute BoardVolunteerBilling.membership_subscription_for_pause?(sub)
    end

    test "rejects non-membership price", %{membership_price_id: price_id} do
      sub = %Subscription{
        stripe_id: "sub_x",
        stripe_status: "active",
        subscription_items: [
          %SubscriptionItem{stripe_price_id: "#{price_id}_other"}
        ]
      }

      refute BoardVolunteerBilling.membership_subscription_for_pause?(sub)
    end

    test "rejects past_due status", %{membership_price_id: price_id} do
      sub = %Subscription{
        stripe_id: "sub_x",
        stripe_status: "past_due",
        subscription_items: [
          %SubscriptionItem{stripe_price_id: price_id}
        ]
      }

      refute BoardVolunteerBilling.membership_subscription_for_pause?(sub)
    end
  end

  describe "household_on_board?/1" do
    test "returns true when user has a board position" do
      user = user_fixture()
      {:ok, user} = Ysc.Accounts.assign_board_position(user, :treasurer)

      assert BoardVolunteerBilling.household_on_board?(user)
    end

    test "returns true when a family member has a board position" do
      primary = user_fixture()

      sub_account =
        %Ysc.Accounts.User{}
        |> Ysc.Accounts.User.sub_account_registration_changeset(
          %{
            email: "sub-#{System.unique_integer()}@example.com",
            password: valid_user_password(),
            first_name: "Sub",
            last_name: "User",
            phone_number: unique_user_phone(),
            date_of_birth: ~D[1990-01-01]
          },
          primary.id,
          hash_password: true,
          validate_email: true
        )
        |> Ysc.Repo.insert!()

      {:ok, _} = Ysc.Accounts.assign_board_position(sub_account, :secretary)

      assert BoardVolunteerBilling.household_on_board?(primary)
    end

    test "returns false when nobody in the household is on the board" do
      user = user_fixture()
      refute BoardVolunteerBilling.household_on_board?(user)
    end

    test "returns true when a newly linked board member is missing from a stale sub_accounts preload" do
      primary = user_fixture()
      sub = user_fixture()
      {:ok, sub} = Ysc.Accounts.assign_board_position(sub, :treasurer)

      _sub =
        sub
        |> Ecto.Changeset.change(%{
          primary_user_id: primary.id,
          family_relationship: "spouse"
        })
        |> Ysc.Repo.update!()

      primary = Ysc.Repo.preload(primary, :sub_accounts)

      assert BoardVolunteerBilling.household_on_board?(primary)
    end

    test "returns false when a removed board member is still in a stale sub_accounts preload" do
      primary = user_fixture()
      sub = user_fixture()

      sub =
        sub
        |> Ecto.Changeset.change(%{
          primary_user_id: primary.id,
          family_relationship: "child"
        })
        |> Ysc.Repo.update!()

      {:ok, sub} = Ysc.Accounts.assign_board_position(sub, :secretary)

      primary = Ysc.Repo.preload(primary, :sub_accounts)

      sub
      |> Ecto.Changeset.change(%{
        primary_user_id: nil,
        family_relationship: nil
      })
      |> Ysc.Repo.update!()

      refute BoardVolunteerBilling.household_on_board?(primary)
    end
  end

  describe "maybe_pause_collection_params/1" do
    test "returns void pause and clears cancel_at_period_end when on the board" do
      user = user_fixture()
      {:ok, user} = Ysc.Accounts.assign_board_position(user, :president)

      assert %{
               pause_collection: %{behavior: :void},
               cancel_at_period_end: false
             } == BoardVolunteerBilling.maybe_pause_collection_params(user)
    end

    test "returns empty map when household is not on the board" do
      user = user_fixture()

      assert %{} == BoardVolunteerBilling.maybe_pause_collection_params(user)
    end
  end

  describe "sync_for_user/2" do
    test "returns :ok without calling Stripe in test mode" do
      user = user_fixture()
      assert :ok == BoardVolunteerBilling.sync_for_user(user)
    end

    test "records sync target in test when household is on the board" do
      user = user_fixture()
      {:ok, user} = Ysc.Accounts.assign_board_position(user, :president)

      Application.put_env(:ysc, :board_volunteer_billing_sync_recorder, self())

      on_exit(fn ->
        Application.delete_env(:ysc, :board_volunteer_billing_sync_recorder)
      end)

      assert :ok == BoardVolunteerBilling.sync_for_user(user)

      user_id = user.id
      assert_receive {:board_volunteer_sync, ^user_id}
    end

    test "does not record sync for households never on the board" do
      user = user_fixture()

      Application.put_env(:ysc, :board_volunteer_billing_sync_recorder, self())

      on_exit(fn ->
        Application.delete_env(:ysc, :board_volunteer_billing_sync_recorder)
      end)

      assert :ok == BoardVolunteerBilling.sync_for_user(user)
      refute_receive {:board_volunteer_sync, _}
    end

    test "records sync when applying off-board grace after board service" do
      user = user_fixture()

      Application.put_env(:ysc, :board_volunteer_billing_sync_recorder, self())

      on_exit(fn ->
        Application.delete_env(:ysc, :board_volunteer_billing_sync_recorder)
      end)

      assert :ok ==
               BoardVolunteerBilling.sync_for_user(user,
                 apply_off_board_grace?: true
               )

      user_id = user.id
      assert_receive {:board_volunteer_sync, ^user_id}
    end
  end

  describe "sync_after_family_membership_change/2" do
    test "syncs when a board member joins the household" do
      primary = user_fixture()
      sub = user_fixture()
      {:ok, sub} = Ysc.Accounts.assign_board_position(sub, :treasurer)

      sub =
        sub
        |> Ecto.Changeset.change(%{
          primary_user_id: primary.id,
          family_relationship: "spouse"
        })
        |> Ysc.Repo.update!()

      Application.put_env(:ysc, :board_volunteer_billing_sync_recorder, self())

      on_exit(fn ->
        Application.delete_env(:ysc, :board_volunteer_billing_sync_recorder)
      end)

      assert :ok ==
               BoardVolunteerBilling.sync_after_family_membership_change(
                 primary,
                 sub
               )

      primary_id = primary.id
      assert_receive {:board_volunteer_sync, ^primary_id}
    end

    test "applies grace sync when a board member leaves the household" do
      primary = user_fixture()
      sub = user_fixture()

      sub =
        sub
        |> Ecto.Changeset.change(%{
          primary_user_id: primary.id,
          family_relationship: "child"
        })
        |> Ysc.Repo.update!()

      {:ok, sub} = Ysc.Accounts.assign_board_position(sub, :secretary)

      sub =
        sub
        |> Ecto.Changeset.change(%{
          primary_user_id: nil,
          family_relationship: nil
        })
        |> Ysc.Repo.update!()

      refute BoardVolunteerBilling.household_on_board?(primary)

      Application.put_env(:ysc, :board_volunteer_billing_sync_recorder, self())

      on_exit(fn ->
        Application.delete_env(:ysc, :board_volunteer_billing_sync_recorder)
      end)

      assert :ok ==
               BoardVolunteerBilling.sync_after_family_membership_change(
                 primary,
                 sub
               )

      primary_id = primary.id
      assert_receive {:board_volunteer_sync, ^primary_id}
    end

    test "skips sync when neither household nor member is on the board" do
      primary = user_fixture()
      sub = user_fixture()

      sub =
        sub
        |> Ecto.Changeset.change(%{
          primary_user_id: primary.id,
          family_relationship: "child"
        })
        |> Ysc.Repo.update!()

      Application.put_env(:ysc, :board_volunteer_billing_sync_recorder, self())

      on_exit(fn ->
        Application.delete_env(:ysc, :board_volunteer_billing_sync_recorder)
      end)

      assert :ok ==
               BoardVolunteerBilling.sync_after_family_membership_change(
                 primary,
                 sub
               )

      refute_receive {:board_volunteer_sync, _}
    end
  end

  describe "sync_all_board_households/0" do
    test "returns :ok without calling Stripe in test mode" do
      assert :ok == BoardVolunteerBilling.sync_all_board_households()
    end
  end

  describe "stripe_sync_params/1" do
    test "household on board uses void pause without resumes_at and clears cancel_at_period_end" do
      assert %{
               pause_collection: %{behavior: :void},
               cancel_at_period_end: false
             } == BoardVolunteerBilling.stripe_sync_params(true)
    end

    test "household off board sets resumes_at six months ahead without touching cancel" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      assert %{pause_collection: %{behavior: :void, resumes_at: unix}} =
               BoardVolunteerBilling.stripe_sync_params(false)

      refute Map.has_key?(
               BoardVolunteerBilling.stripe_sync_params(false),
               :cancel_at_period_end
             )

      expected_now = BoardVolunteerBilling.grace_resume_at_unix_from(now)

      expected_next =
        BoardVolunteerBilling.grace_resume_at_unix_from(
          DateTime.add(now, 1, :second)
        )

      assert unix in [expected_now, expected_next]
    end
  end

  describe "stripe_pause_collection_params/1" do
    test "household on board uses void pause without resumes_at so Stripe drops a stale grace date" do
      assert %{pause_collection: %{behavior: :void}} ==
               BoardVolunteerBilling.stripe_pause_collection_params(true)
    end
  end

  describe "ci_query_explain_query/0" do
    test "builds a runnable Ecto query for CI query-plan diagnostics" do
      query = BoardVolunteerBilling.ci_query_explain_query()

      assert %Ecto.Query{} = query
      assert Ysc.Repo.all(query) == []
    end
  end

  describe "sync_for_user/2 do_sync/2 (outside test env)" do
    setup :verify_on_exit!

    defp membership_price_id do
      :ysc
      |> Application.fetch_env!(:membership_plans)
      |> Enum.find(&(&1.id == :single))
      |> Map.fetch!(:stripe_price_id)
    end

    defp board_user_with_stripe_subscription(opts \\ []) do
      user = user_fixture()

      user =
        if Keyword.get(opts, :on_board?, true) do
          {:ok, user} = Ysc.Accounts.assign_board_position(user, :president)
          user
        else
          user
        end

      user =
        user
        |> Ecto.Changeset.change(%{
          stripe_id: "cus_board_#{System.unique_integer([:positive])}"
        })
        |> Ysc.Repo.update!()

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_board_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          name: "Membership",
          cancel_at_period_end: Keyword.get(opts, :cancel_at_period_end, true),
          ends_at: Keyword.get(opts, :ends_at, DateTime.utc_now())
        })

      {:ok, _item} =
        Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_id: "si_board_#{System.unique_integer([:positive])}",
          stripe_product_id: "prod_single",
          stripe_price_id: membership_price_id(),
          quantity: 1
        })

      {user, subscription}
    end

    test "returns :ok without contacting Stripe when the primary has no stripe_id" do
      user = user_fixture()
      {:ok, user} = Ysc.Accounts.assign_board_position(user, :president)

      assert :ok ==
               EnvHelper.with_environment("dev", fn ->
                 BoardVolunteerBilling.sync_for_user(user)
               end)
    end

    test "pauses the membership subscription and clears a scheduled cancellation on success" do
      {user, subscription} = board_user_with_stripe_subscription()

      expect(Stripe.SubscriptionMock, :update, fn stripe_id, params ->
        assert stripe_id == subscription.stripe_id
        assert params.pause_collection == %{behavior: :void}
        assert params.cancel_at_period_end == false

        {:ok, Ysc.Stripe.SubscriptionFixtures.subscription(id: stripe_id)}
      end)

      assert :ok ==
               EnvHelper.with_environment("dev", fn ->
                 BoardVolunteerBilling.sync_for_user(user)
               end)

      reloaded = Ysc.Repo.get!(Subscription, subscription.id)
      assert is_nil(reloaded.ends_at)
      assert reloaded.cancel_at_period_end == false
    end

    test "leaves a subscription with no scheduled cancellation untouched after Stripe succeeds" do
      {user, subscription} =
        board_user_with_stripe_subscription(
          cancel_at_period_end: false,
          ends_at: nil
        )

      expect(Stripe.SubscriptionMock, :update, fn stripe_id, _params ->
        {:ok, Ysc.Stripe.SubscriptionFixtures.subscription(id: stripe_id)}
      end)

      assert :ok ==
               EnvHelper.with_environment("dev", fn ->
                 BoardVolunteerBilling.sync_for_user(user)
               end)

      reloaded = Ysc.Repo.get!(Subscription, subscription.id)
      assert reloaded.updated_at == subscription.updated_at
    end

    test "logs and still returns :ok when Stripe rejects the pause_collection update" do
      {user, _subscription} = board_user_with_stripe_subscription()

      expect(Stripe.SubscriptionMock, :update, fn _stripe_id, _params ->
        {:error,
         %Stripe.Error{
           source: :stripe,
           code: :invalid_request_error,
           message: "No such subscription",
           request_id: nil,
           extra: %{},
           user_message: nil
         }}
      end)

      log =
        capture_log(fn ->
          assert :ok ==
                   EnvHelper.with_environment("dev", fn ->
                     BoardVolunteerBilling.sync_for_user(user)
                   end)
        end)

      assert log =~ "Board volunteer Stripe pause_collection sync failed"
    end

    test "applies the off-board grace resume_at and skips clearing cancellation" do
      {user, subscription} =
        board_user_with_stripe_subscription(
          on_board?: false,
          cancel_at_period_end: true
        )

      expect(Stripe.SubscriptionMock, :update, fn stripe_id, params ->
        assert %{behavior: :void, resumes_at: resumes_at} =
                 params.pause_collection

        assert is_integer(resumes_at)
        refute Map.has_key?(params, :cancel_at_period_end)

        {:ok, Ysc.Stripe.SubscriptionFixtures.subscription(id: stripe_id)}
      end)

      assert :ok ==
               EnvHelper.with_environment("dev", fn ->
                 BoardVolunteerBilling.sync_for_user(user,
                   apply_off_board_grace?: true
                 )
               end)

      # Grace sync (leaving the board) must not clear the scheduled cancellation.
      reloaded = Ysc.Repo.get!(Subscription, subscription.id)
      assert reloaded.cancel_at_period_end == true
    end
  end

  describe "sync_all_board_households/0 (outside test env)" do
    test "syncs every household with a board member exactly once" do
      {user, subscription} = board_user_with_stripe_subscription_for_all()

      expect(Stripe.SubscriptionMock, :update, fn stripe_id, _params ->
        {:ok, Ysc.Stripe.SubscriptionFixtures.subscription(id: stripe_id)}
      end)

      assert :ok ==
               EnvHelper.with_environment("dev", fn ->
                 BoardVolunteerBilling.sync_all_board_households()
               end)

      reloaded = Ysc.Repo.get!(Subscription, subscription.id)
      assert reloaded.cancel_at_period_end == false
      assert user.id
    end

    defp board_user_with_stripe_subscription_for_all do
      user = user_fixture()
      {:ok, user} = Ysc.Accounts.assign_board_position(user, :president)

      user =
        user
        |> Ecto.Changeset.change(%{
          stripe_id: "cus_board_all_#{System.unique_integer([:positive])}"
        })
        |> Ysc.Repo.update!()

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_board_all_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          name: "Membership",
          cancel_at_period_end: true,
          ends_at: DateTime.utc_now()
        })

      {:ok, _item} =
        Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_id: "si_board_all_#{System.unique_integer([:positive])}",
          stripe_product_id: "prod_single",
          stripe_price_id:
            :ysc
            |> Application.fetch_env!(:membership_plans)
            |> Enum.find(&(&1.id == :single))
            |> Map.fetch!(:stripe_price_id),
          quantity: 1
        })

      {user, subscription}
    end
  end
end
