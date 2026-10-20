defmodule Ysc.Tickets.ConcurrentCheckoutTest do
  @moduledoc """
  Regression for dual-tab `create_ticket_order/4` before either pending exists.

  Without the per-user/event advisory lock, two LiveViews that both pass
  `prepare_new_checkout_session/2` (no pending yet) both insert — two
  confirmable PaymentIntents for the same event.
  """
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Tickets
  alias Ysc.Tickets.TicketOrder

  setup do
    Ysc.Ledgers.ensure_basic_accounts()

    user =
      user_fixture()
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Ysc.Repo.update!()

    organizer = user_fixture()
    event = event_fixture(%{organizer_id: organizer.id})
    tier = ticket_tier_fixture(%{event_id: event.id, name: "GA", quantity: 50})

    %{user: user, event: event, tier: tier}
  end

  test "concurrent identical checkouts leave one pending order", %{
    sandbox_owner: owner,
    user: user,
    event: event,
    tier: tier
  } do
    parent = self()
    selections = %{tier.id => 1}

    tasks =
      for i <- 1..2 do
        Task.async(fn ->
          Ysc.DataCase.allow_sandbox(self(), owner)
          send(parent, {:ready, i})

          receive do
            :go -> Tickets.create_ticket_order(user.id, event.id, selections)
          after
            5_000 -> {:error, :timeout}
          end
        end)
      end

    for _ <- 1..2, do: assert_receive({:ready, _}, 5_000)
    Enum.each(tasks, &send(&1.pid, :go))
    results = Task.await_many(tasks, 15_000)

    assert Enum.all?(results, &match?({:ok, %TicketOrder{}}, &1))

    pending =
      from(to in TicketOrder,
        where:
          to.user_id == ^user.id and to.event_id == ^event.id and
            to.status == :pending
      )
      |> Repo.all()

    superseded =
      from(to in TicketOrder,
        where:
          to.user_id == ^user.id and to.event_id == ^event.id and
            to.status in [:cancelled, :expired]
      )
      |> Repo.all()

    # Without the advisory lock both inserts could land as pending before either
    # prepare_new_checkout_session ran — two payable carts. Serialized: one
    # pending (the winner), and the loser's first insert is superseded.
    assert length(pending) == 1
    assert length(superseded) == 1
  end

  test "concurrent different selections leave one pending order", %{
    sandbox_owner: owner,
    user: user,
    event: event,
    tier: tier
  } do
    parent = self()

    tasks = [
      Task.async(fn ->
        Ysc.DataCase.allow_sandbox(self(), owner)
        send(parent, {:ready, 1})

        receive do
          :go ->
            Tickets.create_ticket_order(user.id, event.id, %{tier.id => 1})
        after
          5_000 -> {:error, :timeout}
        end
      end),
      Task.async(fn ->
        Ysc.DataCase.allow_sandbox(self(), owner)
        send(parent, {:ready, 2})

        receive do
          :go ->
            Tickets.create_ticket_order(user.id, event.id, %{tier.id => 2})
        after
          5_000 -> {:error, :timeout}
        end
      end)
    ]

    for _ <- 1..2, do: assert_receive({:ready, _}, 5_000)
    Enum.each(tasks, &send(&1.pid, :go))
    results = Task.await_many(tasks, 15_000)

    assert Enum.all?(results, &match?({:ok, %TicketOrder{}}, &1))

    pending =
      from(to in TicketOrder,
        where:
          to.user_id == ^user.id and to.event_id == ^event.id and
            to.status == :pending
      )
      |> Repo.all()

    assert length(pending) == 1
  end
end
