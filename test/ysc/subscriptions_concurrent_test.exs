defmodule Ysc.SubscriptionsConcurrentTest do
  @moduledoc """
  Regression for dual-tab / door-sale `create_stripe_subscription/2` before
  either local row exists.

  Web membership checkout omitted a Stripe Idempotency-Key. Two LiveViews that
  both passed `find_blocking_subscription/1` (no local row yet) both called
  `Stripe.Subscription.create` — two subscriptions / two charges. The default
  key is `membership_sub_\#{user.id}_\#{price}` so overlapping same-plan creates
  replay.

  Door-sale and WP onboarding used to pass *different* keys for the same
  price (`app_membership_…`, `wp_onboarding_…`). Those prefixes are ignored
  so a volunteer tap and a member web submit still replay one subscription.

  Persist now happens inside the advisory-lock transaction, so a follow-up
  create (including a different plan, or cash paid-out-of-band) sees the local
  row instead of minting a second Stripe subscription while the webhook is
  still in flight.
  """
  use Ysc.DataCase, async: false, mox_global_first: true

  import Ysc.AccountsFixtures

  alias Ysc.Subscriptions

  setup :verify_on_exit!

  test "concurrent identical creates persist one local subscription and block the other",
       %{
         sandbox_owner: owner
       } do
    user =
      user_fixture(%{
        stripe_id: "cus_conc_#{System.unique_integer([:positive])}"
      })

    price_id = "price_conc_#{System.unique_integer([:positive])}"
    expected_key = "membership_sub_#{user.id}_#{price_id}"
    parent = self()

    stub(Stripe.SubscriptionMock, :create, fn params, opts ->
      key = opts[:headers]["Idempotency-Key"]
      send(parent, {:stripe_create, key})

      stripe_id =
        case key do
          idempotency when is_binary(idempotency) and idempotency != "" ->
            "sub_from_key_#{:erlang.phash2(idempotency)}"

          _ ->
            "sub_unique_#{System.unique_integer([:positive])}"
        end

      {:ok,
       Ysc.Stripe.SubscriptionFixtures.subscription(
         id: stripe_id,
         customer: params.customer,
         status: "active",
         price_id: price_id,
         subscription_item_id: "si_conc_#{:erlang.phash2(stripe_id)}"
       )}
    end)

    params = %{prices: [%{price: price_id, quantity: 1}]}

    tasks =
      for i <- 1..2 do
        Task.async(fn ->
          Ysc.DataCase.allow_sandbox(self(), owner)
          send(parent, {:ready, i})

          receive do
            :go -> Subscriptions.create_stripe_subscription(user, params)
          after
            5_000 -> {:error, :timeout}
          end
        end)
      end

    for _ <- 1..2, do: assert_receive({:ready, _}, 5_000)
    Enum.each(tasks, &send(&1.pid, :go))
    results = Task.await_many(tasks, 15_000)

    oks =
      Enum.filter(results, &match?({:ok, %Stripe.Subscription{}}, &1))

    errors =
      Enum.filter(
        results,
        &match?({:error, :user_already_has_active_subscription}, &1)
      )

    assert length(oks) == 1
    assert length(errors) == 1

    assert_receive {:stripe_create, key1}, 1_000
    refute_receive {:stripe_create, _}, 50

    hashed = Ysc.Stripe.Idempotency.key(expected_key)
    assert key1 == hashed

    local = Subscriptions.list_subscriptions(user)
    assert length(local) == 1
    assert hd(local).stripe_status == "active"
  end

  test "concurrent creates with different caller keys still persist only one subscription",
       %{
         sandbox_owner: owner
       } do
    user =
      user_fixture(%{
        stripe_id: "cus_conc_#{System.unique_integer([:positive])}"
      })

    price_id = "price_conc_#{System.unique_integer([:positive])}"
    expected_key = "membership_sub_#{user.id}_#{price_id}"
    parent = self()

    stub(Stripe.SubscriptionMock, :create, fn params, opts ->
      key = opts[:headers]["Idempotency-Key"]
      send(parent, {:stripe_create, key})

      stripe_id =
        case key do
          idempotency when is_binary(idempotency) and idempotency != "" ->
            "sub_from_key_#{:erlang.phash2(idempotency)}"

          _ ->
            "sub_unique_#{System.unique_integer([:positive])}"
        end

      {:ok,
       Ysc.Stripe.SubscriptionFixtures.subscription(
         id: stripe_id,
         customer: params.customer,
         status: "active",
         price_id: price_id,
         subscription_item_id: "si_conc_#{:erlang.phash2(stripe_id)}"
       )}
    end)

    caller_keys = [
      "app_membership_#{user.id}_#{price_id}",
      "wp_onboarding_#{user.id}_single"
    ]

    tasks =
      for {caller_key, i} <- Enum.with_index(caller_keys, 1) do
        Task.async(fn ->
          Ysc.DataCase.allow_sandbox(self(), owner)
          send(parent, {:ready, i})

          receive do
            :go ->
              Subscriptions.create_stripe_subscription(user, %{
                prices: [%{price: price_id, quantity: 1}],
                idempotency_key: caller_key
              })
          after
            5_000 -> {:error, :timeout}
          end
        end)
      end

    for _ <- 1..2, do: assert_receive({:ready, _}, 5_000)
    Enum.each(tasks, &send(&1.pid, :go))
    results = Task.await_many(tasks, 15_000)

    oks =
      Enum.filter(results, &match?({:ok, %Stripe.Subscription{}}, &1))

    errors =
      Enum.filter(
        results,
        &match?({:error, :user_already_has_active_subscription}, &1)
      )

    assert length(oks) == 1
    assert length(errors) == 1

    assert_receive {:stripe_create, key1}, 1_000
    refute_receive {:stripe_create, _}, 50

    hashed = Ysc.Stripe.Idempotency.key(expected_key)
    assert key1 == hashed

    local = Subscriptions.list_subscriptions(user)
    assert length(local) == 1
  end
end
