defmodule Ysc.Merch.OrdersInFlightTest do
  use Ysc.DataCase, async: false

  import Mox
  import Ysc.AccountsFixtures
  import Ysc.MerchFixtures

  alias Ysc.Merch.{Order, Orders}
  alias Ysc.StripeMock

  setup :verify_on_exit!

  setup do
    original = Application.get_env(:ysc, :stripe_client)
    Application.put_env(:ysc, :stripe_client, StripeMock)
    on_exit(fn -> Application.put_env(:ysc, :stripe_client, original) end)

    user = user_fixture()

    tee =
      variant_fixture(nil, %{
        retail_price: Money.new(:USD, "25"),
        name: "Tee / Black / M"
      })

    lines = cart_lines_fixture(user, [{tee, 2}])
    %{user: user, tee: tee, lines: lines}
  end

  defp create(user, lines, opts \\ []) do
    Orders.create_pending_purchase(
      user,
      lines,
      Keyword.get(opts, :address, shipping_address_fixture()),
      Keyword.get(opts, :option, shipping_option_fixture())
    )
  end

  defp intent(id, status) do
    {:ok,
     %Stripe.PaymentIntent{
       id: id,
       status: status,
       amount: 5595
     }}
  end

  test "refuses a different cart while a processing PaymentIntent is in flight",
       %{
         user: user,
         lines: lines,
         tee: tee
       } do
    {:ok, first} = create(user, lines)
    {:ok, _} = Orders.attach_payment_intent(first, "pi_processing")

    expect(StripeMock, :retrieve_payment_intent, fn "pi_processing", _ ->
      intent("pi_processing", "processing")
    end)

    {:ok, _} = Ysc.Merch.Cart.set_quantity(user, tee.id, 3)

    assert {:error, :payment_in_progress} =
             create(user, Ysc.Merch.Cart.list(user))

    assert Repo.aggregate(Order, :count) == 1
    assert Orders.get_order!(first.id).status == :pending
    assert Orders.get_order!(first.id).payment_intent_id == "pi_processing"
  end

  test "refuses a different address while a processing PaymentIntent is in flight",
       %{user: user, lines: lines} do
    {:ok, first} = create(user, lines)
    {:ok, _} = Orders.attach_payment_intent(first, "pi_processing")

    expect(StripeMock, :retrieve_payment_intent, fn "pi_processing", _ ->
      intent("pi_processing", "processing")
    end)

    assert {:error, :payment_in_progress} =
             create(user, lines,
               address: shipping_address_fixture(%{"zip" => "94106"})
             )

    assert Repo.aggregate(Order, :count) == 1
  end

  test "refuses a different cart for every other in-flight PaymentIntent status",
       %{tee: tee} do
    for status <- ~w(requires_action requires_confirmation succeeded) do
      user = user_fixture()
      lines = cart_lines_fixture(user, [{tee, 2}])
      {:ok, first} = create(user, lines)
      payment_intent_id = "pi_#{status}"
      {:ok, _} = Orders.attach_payment_intent(first, payment_intent_id)

      expect(StripeMock, :retrieve_payment_intent, fn ^payment_intent_id, _ ->
        intent(payment_intent_id, status)
      end)

      {:ok, _} = Ysc.Merch.Cart.set_quantity(user, tee.id, 3)

      assert {:error, :payment_in_progress} =
               create(user, Ysc.Merch.Cart.list(user))

      assert Orders.get_order!(first.id).status == :pending
      assert Orders.get_order!(first.id).payment_intent_id == payment_intent_id
    end
  end

  test "Stripe-cancels an unpaid prior Intent before a different-cart checkout",
       %{
         user: user,
         lines: lines,
         tee: tee
       } do
    {:ok, first} = create(user, lines)
    {:ok, _} = Orders.attach_payment_intent(first, "pi_open")

    expect(StripeMock, :retrieve_payment_intent, fn "pi_open", _ ->
      intent("pi_open", "requires_payment_method")
    end)

    expect(StripeMock, :cancel_payment_intent, fn "pi_open", _ ->
      intent("pi_open", "canceled")
    end)

    {:ok, _} = Ysc.Merch.Cart.set_quantity(user, tee.id, 3)
    assert {:ok, second} = create(user, Ysc.Merch.Cart.list(user))
    refute second.id == first.id

    first = Orders.get_order!(first.id)
    assert first.status == :canceled
    assert first.failure_reason == "Superseded by new checkout"
    assert second.status == :pending
  end

  test "cancels a pending checkout that never attached a PaymentIntent", %{
    user: user,
    lines: lines,
    tee: tee
  } do
    {:ok, first} = create(user, lines)
    {:ok, _} = Ysc.Merch.Cart.set_quantity(user, tee.id, 3)

    assert {:ok, second} = create(user, Ysc.Merch.Cart.list(user))
    refute second.id == first.id
    assert Orders.get_order!(first.id).status == :canceled

    assert Orders.get_order!(first.id).failure_reason ==
             "Superseded by new checkout"
  end

  test "refuses a different cart when Stripe cannot say the stored Intent is idle",
       %{
         user: user,
         lines: lines,
         tee: tee
       } do
    {:ok, first} = create(user, lines)
    {:ok, _} = Orders.attach_payment_intent(first, "pi_outage")

    expect(StripeMock, :retrieve_payment_intent, fn "pi_outage", _ ->
      {:error,
       %Stripe.Error{source: :stripe, code: :api_error, message: "down"}}
    end)

    {:ok, _} = Ysc.Merch.Cart.set_quantity(user, tee.id, 3)

    assert {:error, :payment_in_progress} =
             create(user, Ysc.Merch.Cart.list(user))

    assert Repo.aggregate(Order, :count) == 1
    assert Orders.get_order!(first.id).status == :pending
    assert Orders.get_order!(first.id).payment_intent_id == "pi_outage"
  end

  test "concurrent identical checkouts reuse one pending order", %{
    sandbox_owner: owner,
    user: user,
    lines: lines
  } do
    parent = self()

    tasks =
      for i <- 1..2 do
        Task.async(fn ->
          Ysc.DataCase.allow_sandbox(self(), owner)
          send(parent, {:ready, i})

          receive do
            :go -> create(user, lines)
          after
            5_000 -> {:error, :timeout}
          end
        end)
      end

    for _ <- 1..2, do: assert_receive({:ready, _}, 5_000)
    Enum.each(tasks, &send(&1.pid, :go))
    results = Task.await_many(tasks, 15_000)

    assert Enum.all?(results, &match?({:ok, %Order{}}, &1))

    ids =
      results
      |> Enum.map(fn {:ok, order} -> order.id end)
      |> Enum.uniq()

    assert length(ids) == 1

    pending =
      from(o in Order, where: o.status == :pending)
      |> Repo.all()

    assert length(pending) == 1
    assert hd(pending).id == hd(ids)
  end

  test "concurrent different-cart checkouts leave one pending order", %{
    sandbox_owner: owner,
    user: user,
    tee: tee,
    lines: lines
  } do
    {:ok, _} = Ysc.Merch.Cart.set_quantity(user, tee.id, 3)
    other_lines = Ysc.Merch.Cart.list(user)
    parent = self()

    tasks = [
      Task.async(fn ->
        Ysc.DataCase.allow_sandbox(self(), owner)
        send(parent, {:ready, 1})

        receive do
          :go -> create(user, lines)
        after
          5_000 -> {:error, :timeout}
        end
      end),
      Task.async(fn ->
        Ysc.DataCase.allow_sandbox(self(), owner)
        send(parent, {:ready, 2})

        receive do
          :go -> create(user, other_lines)
        after
          5_000 -> {:error, :timeout}
        end
      end)
    ]

    for _ <- 1..2, do: assert_receive({:ready, _}, 5_000)
    Enum.each(tasks, &send(&1.pid, :go))
    results = Task.await_many(tasks, 15_000)

    assert Enum.all?(results, &match?({:ok, %Order{}}, &1))

    pending =
      from(o in Order, where: o.status == :pending)
      |> Repo.all()

    canceled =
      from(o in Order, where: o.status == :canceled)
      |> Repo.all()

    # Without the advisory lock both inserts could land as pending before either
    # supersede ran — two payable carts. Serialized: one pending, one canceled.
    assert length(pending) == 1
    assert length(canceled) == 1
  end

  test "refuses a different cart when canceling the prior Intent fails", %{
    user: user,
    lines: lines,
    tee: tee
  } do
    {:ok, first} = create(user, lines)
    {:ok, _} = Orders.attach_payment_intent(first, "pi_flaky")

    expect(StripeMock, :retrieve_payment_intent, fn "pi_flaky", _ ->
      intent("pi_flaky", "requires_payment_method")
    end)

    expect(StripeMock, :cancel_payment_intent, fn "pi_flaky", _ ->
      {:error,
       %Stripe.Error{
         source: :stripe,
         code: :api_error,
         message: "stripe unavailable"
       }}
    end)

    expect(StripeMock, :retrieve_payment_intent, fn "pi_flaky", _ ->
      {:error,
       %Stripe.Error{
         source: :stripe,
         code: :api_error,
         message: "stripe unavailable"
       }}
    end)

    {:ok, _} = Ysc.Merch.Cart.set_quantity(user, tee.id, 3)

    assert {:error, :payment_in_progress} =
             create(user, Ysc.Merch.Cart.list(user))

    assert Orders.get_order!(first.id).status == :pending
    assert Repo.aggregate(Order, :count) == 1
  end

  test "refuses a different cart when the unpaid Intent succeeds between retrieve and cancel",
       %{
         user: user,
         lines: lines,
         tee: tee
       } do
    {:ok, first} = create(user, lines)
    {:ok, _} = Orders.attach_payment_intent(first, "pi_raced_paid")

    expect_idle_then_uncancellable("pi_raced_paid", "succeeded")

    {:ok, _} = Ysc.Merch.Cart.set_quantity(user, tee.id, 3)

    assert {:error, :payment_in_progress} =
             create(user, Ysc.Merch.Cart.list(user))

    assert Repo.aggregate(Order, :count) == 1
    assert Orders.get_order!(first.id).status == :pending
    assert Orders.get_order!(first.id).payment_intent_id == "pi_raced_paid"
  end

  test "refuses a different cart when the unpaid Intent starts processing between retrieve and cancel",
       %{
         user: user,
         lines: lines,
         tee: tee
       } do
    {:ok, first} = create(user, lines)
    {:ok, _} = Orders.attach_payment_intent(first, "pi_raced_ach")

    expect_idle_then_uncancellable("pi_raced_ach", "processing")

    {:ok, _} = Ysc.Merch.Cart.set_quantity(user, tee.id, 3)

    assert {:error, :payment_in_progress} =
             create(user, Ysc.Merch.Cart.list(user))

    assert Repo.aggregate(Order, :count) == 1
    assert Orders.get_order!(first.id).status == :pending
    assert Orders.get_order!(first.id).payment_intent_id == "pi_raced_ach"
  end

  test "refuses a different cart when Stripe cancel succeeds but the pending row is already gone",
       %{
         user: user,
         lines: lines,
         tee: tee
       } do
    {:ok, first} = create(user, lines)
    {:ok, _} = Orders.attach_payment_intent(first, "pi_raced_row")

    expect(StripeMock, :retrieve_payment_intent, fn "pi_raced_row", _ ->
      intent("pi_raced_row", "requires_payment_method")
    end)

    expect(StripeMock, :cancel_payment_intent, fn "pi_raced_row", _ ->
      order = Repo.get!(Order, first.id)

      {:ok, _} =
        order
        |> Ecto.Changeset.change(status: :paid)
        |> Repo.update()

      intent("pi_raced_row", "canceled")
    end)

    {:ok, _} = Ysc.Merch.Cart.set_quantity(user, tee.id, 3)

    assert {:error, :payment_in_progress} =
             create(user, Ysc.Merch.Cart.list(user))

    # The cancel mock writes :paid so local cancel_pending/2 returns
    # :not_pending and we refuse a second order. create_pending_purchase/4
    # rolls that transaction back on error, so the row is :pending again
    # in this sandbox — a production webhook would commit on another
    # connection. The refuse + single-row check is the invariant.
    assert Orders.get_order!(first.id).status == :pending
    assert Repo.aggregate(Order, :count) == 1
  end

  defp expect_idle_then_uncancellable(payment_intent_id, later_status) do
    expect(StripeMock, :retrieve_payment_intent, fn ^payment_intent_id, _ ->
      intent(payment_intent_id, "requires_payment_method")
    end)

    expect(StripeMock, :cancel_payment_intent, fn ^payment_intent_id, _ ->
      {:error,
       %Stripe.Error{
         source: :stripe,
         code: :payment_intent_unexpected_state,
         message: "cannot cancel",
         extra: %{}
       }}
    end)

    expect(StripeMock, :retrieve_payment_intent, fn ^payment_intent_id, opts ->
      assert opts[:expand] == ["latest_charge"]
      intent(payment_intent_id, later_status)
    end)
  end
end
