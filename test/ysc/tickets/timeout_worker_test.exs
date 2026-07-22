defmodule Ysc.Tickets.TimeoutWorkerTest do
  @moduledoc """
  Tests for Ysc.Tickets.TimeoutWorker.
  """
  use Ysc.DataCase, async: true

  alias Ysc.Tickets.TimeoutWorker
  alias Ysc.Tickets
  alias Ysc.Tickets.TicketOrder
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  setup do
    oban_config = Application.get_env(:ysc, Oban, [])

    Application.put_env(:ysc, Oban, Keyword.put(oban_config, :testing, :manual))
    on_exit(fn -> Application.put_env(:ysc, Oban, oban_config) end)

    user = user_fixture()
    event = event_fixture()
    %{user: user, event: event}
  end

  describe "perform/1" do
    test "reports zero expired when no pending orders have passed expires_at",
         %{
           user: user,
           event: event
         } do
      %TicketOrder{
        user_id: user.id,
        event_id: event.id,
        status: :pending,
        total_amount: Money.new(1000, :USD),
        reference_id: "TO-SOON-#{System.unique_integer([:positive])}",
        expires_at:
          DateTime.utc_now()
          |> DateTime.add(7200, :second)
          |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

      assert {:ok, message} = TimeoutWorker.perform(%Oban.Job{args: %{}})
      assert message =~ "Expired 0 timed out ticket orders"
    end

    test "expires timed out orders", %{user: user, event: event} do
      # Create an expired order
      order =
        %TicketOrder{
          user_id: user.id,
          event_id: event.id,
          status: :pending,
          total_amount: Money.new(1000, :USD),
          reference_id: "TO-EXPIRED",
          expires_at:
            DateTime.utc_now()
            |> DateTime.add(-3600, :second)
            |> DateTime.truncate(:second)
        }
        |> Repo.insert!()

      # Run worker
      assert {:ok, message} = TimeoutWorker.perform(%Oban.Job{args: %{}})
      assert message =~ "Expired"
      assert message =~ "timed out ticket orders"

      # Verify order status
      updated_order = Tickets.get_ticket_order(order.id)
      assert updated_order.status == :expired
    end

    test "does not expire valid orders", %{user: user, event: event} do
      # Create a valid order
      order =
        %TicketOrder{
          user_id: user.id,
          event_id: event.id,
          status: :pending,
          total_amount: Money.new(1000, :USD),
          reference_id: "TO-VALID",
          expires_at:
            DateTime.utc_now()
            |> DateTime.add(3600, :second)
            |> DateTime.truncate(:second)
        }
        |> Repo.insert!()

      # Run worker
      assert {:ok, message} = TimeoutWorker.perform(%Oban.Job{args: %{}})
      assert message =~ "Expired"
      assert message =~ "timed out ticket orders"

      # Verify order status
      updated_order = Tickets.get_ticket_order(order.id)
      assert updated_order.status == :pending
    end

    test "perform_job runs default batch expiration", %{
      user: user,
      event: event
    } do
      %TicketOrder{
        user_id: user.id,
        event_id: event.id,
        status: :pending,
        total_amount: Money.new(1000, :USD),
        reference_id: "TO-PJ-DEFAULT",
        expires_at:
          DateTime.utc_now()
          |> DateTime.add(-3600, :second)
          |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

      assert {:ok, message} = perform_job(TimeoutWorker, %{})
      assert message =~ "Expired"
    end

    test "schedule_next action expires batch and enqueues follow-up check", %{
      user: user,
      event: event
    } do
      %TicketOrder{
        user_id: user.id,
        event_id: event.id,
        status: :pending,
        total_amount: Money.new(1000, :USD),
        reference_id: "TO-SCHED-NEXT",
        expires_at:
          DateTime.utc_now()
          |> DateTime.add(-120, :second)
          |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

      assert {:ok, message} =
               TimeoutWorker.perform(%Oban.Job{
                 args: %{"action" => "schedule_next"}
               })

      assert message =~ "scheduled next check"
    end

    test "handles specific order expiration", %{user: user, event: event} do
      order =
        %TicketOrder{
          user_id: user.id,
          event_id: event.id,
          status: :pending,
          total_amount: Money.new(1000, :USD),
          reference_id: "TO-SPECIFIC",
          expires_at:
            DateTime.utc_now()
            |> DateTime.add(-60, :second)
            |> DateTime.truncate(:second)
        }
        |> Repo.insert!()

      assert {:ok, "Expired specific ticket order"} =
               TimeoutWorker.perform(%Oban.Job{
                 args: %{"ticket_order_id" => order.id}
               })

      updated_order = Tickets.get_ticket_order(order.id)
      assert updated_order.status == :expired
    end

    test "skips specific order expiration before expires_at", %{
      user: user,
      event: event
    } do
      order =
        %TicketOrder{
          user_id: user.id,
          event_id: event.id,
          status: :pending,
          total_amount: Money.new(1000, :USD),
          reference_id: "TO-SPECIFIC-SOON",
          expires_at:
            DateTime.utc_now()
            |> DateTime.add(3600, :second)
            |> DateTime.truncate(:second)
        }
        |> Repo.insert!()

      assert {:ok, "Expired specific ticket order"} =
               TimeoutWorker.perform(%Oban.Job{
                 args: %{"ticket_order_id" => order.id}
               })

      updated_order = Tickets.get_ticket_order(order.id)
      assert updated_order.status == :pending
    end
  end

  describe "scheduling" do
    test "schedule_timeout_check/0 enqueues a default expiration job" do
      assert {:ok, job} = TimeoutWorker.schedule_timeout_check()
      assert job.worker == "Ysc.Tickets.TimeoutWorker"
      assert job.args == %{}
    end

    test "schedule_order_timeout/2 schedules a job" do
      expires_at = DateTime.utc_now() |> DateTime.add(300, :second)
      ticket_order_id = Ecto.ULID.generate()

      assert {:ok, job} =
               TimeoutWorker.schedule_order_timeout(ticket_order_id, expires_at)

      assert job.args["ticket_order_id"] == ticket_order_id
      assert job.worker == "Ysc.Tickets.TimeoutWorker"
    end

    test "schedule_order_timeout/2 enqueues immediately when already past expiration" do
      ticket_order_id = Ecto.ULID.generate()
      expires_at = DateTime.utc_now() |> DateTime.add(-60, :second)

      assert {:ok, job} =
               TimeoutWorker.schedule_order_timeout(ticket_order_id, expires_at)

      assert job.args["ticket_order_id"] == ticket_order_id
      assert job.worker == "Ysc.Tickets.TimeoutWorker"
    end
  end

  describe "expire_specific_order/1" do
    test "returns ok when ticket order does not exist" do
      assert :ok = TimeoutWorker.expire_specific_order(Ecto.ULID.generate())
    end

    test "returns ok when order is not pending", %{user: user, event: event} do
      order =
        %TicketOrder{
          user_id: user.id,
          event_id: event.id,
          status: :completed,
          total_amount: Money.new(1000, :USD),
          reference_id: "TO-NOT-PENDING",
          expires_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }
        |> Repo.insert!()

      assert :ok = TimeoutWorker.expire_specific_order(order.id)

      assert Tickets.get_ticket_order(order.id).status == :completed
    end

    test "returns ok without expiring when order is pending but not yet due", %{
      user: user,
      event: event
    } do
      order =
        %TicketOrder{
          user_id: user.id,
          event_id: event.id,
          status: :pending,
          total_amount: Money.new(0, :USD),
          reference_id: "TO-NOT-YET-DUE",
          expires_at:
            DateTime.utc_now()
            |> DateTime.add(3600, :second)
            |> DateTime.truncate(:second)
        }
        |> Repo.insert!()

      assert :ok = TimeoutWorker.expire_specific_order(order.id)
      assert Tickets.get_ticket_order(order.id).status == :pending
    end

    test "expires pending orders that are past expires_at", %{
      user: user,
      event: event
    } do
      order =
        %TicketOrder{
          user_id: user.id,
          event_id: event.id,
          status: :pending,
          total_amount: Money.new(0, :USD),
          reference_id: "TO-PAST-DUE",
          expires_at:
            DateTime.utc_now()
            |> DateTime.add(-60, :second)
            |> DateTime.truncate(:second)
        }
        |> Repo.insert!()

      assert :ok = TimeoutWorker.expire_specific_order(order.id)
      assert Tickets.get_ticket_order(order.id).status == :expired
    end

    test "batch expiration does not revert completed orders", %{
      user: user,
      event: event
    } do
      order =
        %TicketOrder{
          user_id: user.id,
          event_id: event.id,
          status: :completed,
          total_amount: Money.new(1000, :USD),
          reference_id: "TO-BATCH-COMPLETED",
          expires_at:
            DateTime.utc_now()
            |> DateTime.add(-3600, :second)
            |> DateTime.truncate(:second)
        }
        |> Repo.insert!()

      assert {:ok, _message} = TimeoutWorker.perform(%Oban.Job{args: %{}})

      assert Tickets.get_ticket_order(order.id).status == :completed
    end
  end

  describe "worker timeout" do
    test "timeout/1 returns 30 seconds" do
      assert TimeoutWorker.timeout(%Oban.Job{}) == 30_000
    end
  end
end
