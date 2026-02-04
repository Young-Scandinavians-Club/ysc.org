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
    Application.put_env(:ysc, Oban, testing: :manual)
    on_exit(fn -> Application.put_env(:ysc, Oban, testing: :inline) end)

    user = user_fixture()
    event = event_fixture()
    %{user: user, event: event}
  end

  describe "perform/1" do
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
            |> DateTime.add(3600, :second)
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
  end

  describe "scheduling" do
    test "schedule_order_timeout/2 schedules a job" do
      expires_at = DateTime.utc_now() |> DateTime.add(300, :second)
      ticket_order_id = Ecto.ULID.generate()

      assert {:ok, job} =
               TimeoutWorker.schedule_order_timeout(ticket_order_id, expires_at)

      assert job.args["ticket_order_id"] == ticket_order_id
      assert job.worker == "Ysc.Tickets.TimeoutWorker"
    end
  end
end
