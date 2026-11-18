defmodule Ysc.Tickets.MaxPerBuyerCashOnlineRaceTest do
  @moduledoc """
  #1856 leftover: cash door grants and online checkout must share the
  per-(user, event) advisory lock and re-check `max_per_buyer` under it.

  Before the fix, `validate_tier_purchase_limits/4` ran outside the lock on
  both paths, and `AdminGrants` never took the checkout lock — so a cash
  sale and an overlapping online create could each see 0 confirmed tickets
  and both succeed for `max_per_buyer: 1`.
  """
  use Ysc.DataCase, async: false

  import Ecto.Query
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Events.Ticket
  alias Ysc.Repo
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
      |> Repo.update!()

    admin = user_fixture(%{role: :admin})
    event = event_fixture()

    tier =
      ticket_tier_fixture(%{
        event_id: event.id,
        name: "Guest (+1)",
        quantity: 50,
        max_per_buyer: 1
      })

    %{user: user, admin: admin, event: event, tier: tier}
  end

  test "concurrent cash grant and online checkout cannot both take the last seat",
       %{
         sandbox_owner: owner,
         user: user,
         admin: admin,
         event: event,
         tier: tier
       } do
    parent = self()
    selections = %{tier.id => 1}

    cash_task =
      Task.async(fn ->
        Ysc.DataCase.allow_sandbox(self(), owner)
        send(parent, {:ready, :cash})

        receive do
          :go ->
            # Mirror AppTicketsController.grant_offline_order: validate then grant.
            with :ok <-
                   Tickets.validate_tier_purchase_limits(
                     user,
                     event.id,
                     selections,
                     [tier]
                   ) do
              Tickets.grant_admin_tickets(
                admin.id,
                user.id,
                event.id,
                selections,
                skip_email: true,
                skip_capacity: true,
                skip_sale_guards: true,
                enforce_max_per_buyer: true,
                payment_channel: "cash",
                user: user,
                event: event,
                tiers: [tier]
              )
            end
        after
          5_000 -> {:error, :timeout}
        end
      end)

    online_task =
      Task.async(fn ->
        Ysc.DataCase.allow_sandbox(self(), owner)
        send(parent, {:ready, :online})

        receive do
          :go ->
            Tickets.create_ticket_order(user.id, event.id, selections,
              user: user,
              event: event,
              tiers: [tier]
            )
        after
          5_000 -> {:error, :timeout}
        end
      end)

    for _ <- 1..2, do: assert_receive({:ready, _}, 5_000)
    send(cash_task.pid, :go)
    send(online_task.pid, :go)

    [cash_result, online_result] =
      Task.await_many([cash_task, online_task], 15_000)

    # Either side may "win" the lock. When online inserts first, cash cancels
    # that pending cart and both Tasks can return {:ok, %TicketOrder{}} — the
    # online order is then cancelled. When cash inserts first, online must
    # fail the under-lock max_per_buyer re-check.
    assert match?({:ok, %TicketOrder{}}, cash_result) or
             match?({:ok, %TicketOrder{}}, online_result)

    if match?({:ok, %TicketOrder{}}, cash_result) and
         match?({:ok, %TicketOrder{}}, online_result) do
      {:ok, online_order} = online_result
      reloaded = Repo.get!(TicketOrder, online_order.id)
      assert reloaded.status in [:cancelled, :expired]
    end

    if match?({:error, _}, online_result) do
      assert online_result in [
               {:error, :tier_purchase_limit_exceeded},
               {:error, :checkout_payment_in_progress}
             ]
    end

    confirmed =
      from(t in Ticket,
        where:
          t.user_id == ^user.id and t.event_id == ^event.id and
            t.ticket_tier_id == ^tier.id and t.status == :confirmed
      )
      |> Repo.aggregate(:count)

    pending =
      from(t in Ticket,
        where:
          t.user_id == ^user.id and t.event_id == ^event.id and
            t.ticket_tier_id == ^tier.id and t.status == :pending
      )
      |> Repo.aggregate(:count)

    # Never leave a payable pending on top of a confirmed cash grant (or two
    # confirmed seats) for max_per_buyer: 1.
    assert confirmed + pending <= 1
  end

  test "concurrent cash grants cannot both confirm under max_per_buyer", %{
    sandbox_owner: owner,
    user: user,
    admin: admin,
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
            :go ->
              with :ok <-
                     Tickets.validate_tier_purchase_limits(
                       user,
                       event.id,
                       selections,
                       [tier]
                     ) do
                Tickets.grant_admin_tickets(
                  admin.id,
                  user.id,
                  event.id,
                  selections,
                  skip_email: true,
                  skip_capacity: true,
                  skip_sale_guards: true,
                  enforce_max_per_buyer: true,
                  payment_channel: "cash",
                  user: user,
                  event: event,
                  tiers: [tier]
                )
              end
          after
            5_000 -> {:error, :timeout}
          end
        end)
      end

    for _ <- 1..2, do: assert_receive({:ready, _}, 5_000)
    Enum.each(tasks, &send(&1.pid, :go))
    results = Task.await_many(tasks, 15_000)

    assert Enum.count(results, &match?({:ok, %TicketOrder{}}, &1)) == 1

    assert Enum.any?(
             results,
             &match?({:error, :tier_purchase_limit_exceeded}, &1)
           )

    confirmed =
      from(t in Ticket,
        where:
          t.user_id == ^user.id and t.event_id == ^event.id and
            t.ticket_tier_id == ^tier.id and t.status == :confirmed
      )
      |> Repo.aggregate(:count)

    assert confirmed == 1
  end

  test "complimentary admin grant without payment_channel may still exceed max_per_buyer",
       %{
         user: user,
         admin: admin,
         event: event,
         tier: tier
       } do
    assert {:ok, _} =
             Tickets.grant_admin_tickets(
               admin.id,
               user.id,
               event.id,
               %{tier.id => 1},
               skip_email: true
             )

    assert {:ok, _} =
             Tickets.grant_admin_tickets(
               admin.id,
               user.id,
               event.id,
               %{tier.id => 1},
               skip_email: true
             )

    confirmed =
      from(t in Ticket,
        where:
          t.user_id == ^user.id and t.event_id == ^event.id and
            t.ticket_tier_id == ^tier.id and t.status == :confirmed
      )
      |> Repo.aggregate(:count)

    assert confirmed == 2
  end

  test "enforce_max_per_buyer without payment_channel still serializes under the lock",
       %{
         user: user,
         admin: admin,
         event: event,
         tier: tier
       } do
    assert {:ok, _} =
             Tickets.grant_admin_tickets(
               admin.id,
               user.id,
               event.id,
               %{tier.id => 1},
               skip_email: true,
               enforce_max_per_buyer: true
             )

    assert {:error, :tier_purchase_limit_exceeded} =
             Tickets.grant_admin_tickets(
               admin.id,
               user.id,
               event.id,
               %{tier.id => 1},
               skip_email: true,
               enforce_max_per_buyer: true
             )
  end

  # AppTicketsController now also passes `enforce_max_per_buyer: true`, but
  # the domain contract is that cash/check/other alone implies the re-check.
  # Without this, dropping the implied-channel clause still passes the
  # explicit-flag tests above.
  for channel <- ["cash", "check", "other"] do
    test "payment_channel #{channel} implies max_per_buyer without enforce_max_per_buyer",
         %{
           user: user,
           admin: admin,
           event: event,
           tier: tier
         } do
      channel = unquote(channel)

      assert {:ok, _} =
               Tickets.grant_admin_tickets(
                 admin.id,
                 user.id,
                 event.id,
                 %{tier.id => 1},
                 skip_email: true,
                 payment_channel: channel
               )

      assert {:error, :tier_purchase_limit_exceeded} =
               Tickets.grant_admin_tickets(
                 admin.id,
                 user.id,
                 event.id,
                 %{tier.id => 1},
                 skip_email: true,
                 payment_channel: channel
               )
    end
  end

  test "online checkout is rejected after a cash door grant at the limit", %{
    user: user,
    admin: admin,
    event: event,
    tier: tier
  } do
    assert {:ok, _} =
             Tickets.grant_admin_tickets(
               admin.id,
               user.id,
               event.id,
               %{tier.id => 1},
               skip_email: true,
               payment_channel: "cash"
             )

    assert {:error, :tier_purchase_limit_exceeded} =
             Tickets.create_ticket_order(user.id, event.id, %{tier.id => 1},
               user: user,
               event: event,
               tiers: [tier]
             )
  end
end
