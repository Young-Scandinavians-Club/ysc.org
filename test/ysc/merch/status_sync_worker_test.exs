defmodule Ysc.Merch.StatusSyncWorkerTest do
  use Ysc.DataCase, async: false

  import Mox
  import Swoosh.TestAssertions
  import Ysc.MerchFixtures

  alias Ysc.Merch.{Orders, StatusSyncWorker}
  alias Ysc.Printful.{ClientMock, Error}

  setup :verify_on_exit!

  defp run, do: assert(:ok = StatusSyncWorker.perform(%Oban.Job{}))
  defp status(order), do: Orders.get_order!(order.id).status

  test "picks up what Printful says about orders in flight" do
    member = member_fixture()
    order = purchase_order_fixture(member, :submitted)

    expect(ClientMock, :get_order, fn id ->
      assert id == order.printful_order_id

      {:ok,
       %{
         "id" => id,
         "external_id" => order.reference_id,
         "status" => "fulfilled",
         "costs" => %{"total" => "27.50"},
         "shipments" => [printful_shipment()]
       }}
    end)

    run()

    synced = Orders.get_order!(order.id)
    assert synced.status == :shipped
    assert Money.equal?(synced.printful_cost, Money.new(:USD, "27.50"))
    assert synced.printful_synced_at
    assert_email_sent(subject: ~r/on its way/)
  end

  test "ignores orders that are not in flight or not yet known to Printful" do
    member = member_fixture()
    _pending = purchase_order_fixture(member, :pending)
    _paid = purchase_order_fixture(member, :paid)
    _delivered = purchase_order_fixture(member, :delivered)
    _failed = purchase_order_fixture(member, :failed)

    # No expectation: any Printful call would fail verification.
    run()
  end

  test "ignores orders too old to be worth polling" do
    member = member_fixture()
    order = purchase_order_fixture(member, :submitted)

    old =
      DateTime.add(DateTime.utc_now(), -61 * 86_400, :second)
      |> DateTime.truncate(:second)

    order |> Ecto.Changeset.change(inserted_at: old) |> Repo.update!()

    run()
    assert status(order) == :submitted
  end

  test "checks the least recently synced order first" do
    member = member_fixture()
    recent = purchase_order_fixture(member, :submitted)
    stale = purchase_order_fixture(member, :submitted)
    never = purchase_order_fixture(member, :submitted)

    now = DateTime.truncate(DateTime.utc_now(), :second)
    recent |> Ecto.Changeset.change(printful_synced_at: now) |> Repo.update!()

    stale
    |> Ecto.Changeset.change(
      printful_synced_at: DateTime.add(now, -3600, :second)
    )
    |> Repo.update!()

    test_pid = self()

    stub(ClientMock, :get_order, fn id ->
      send(test_pid, {:polled, id})
      {:ok, %{"id" => id, "status" => "pending"}}
    end)

    run()

    assert_received {:polled, first}
    assert_received {:polled, second}
    assert_received {:polled, third}

    assert [first, second, third] ==
             [
               never.printful_order_id,
               stale.printful_order_id,
               recent.printful_order_id
             ]
  end

  test "a Printful error for one order does not stop the rest" do
    member = member_fixture()
    broken = purchase_order_fixture(member, :submitted)
    fine = purchase_order_fixture(member, :submitted)

    stub(ClientMock, :get_order, fn id ->
      if id == broken.printful_order_id do
        {:error, %Error{type: :server, status: 500, message: "boom"}}
      else
        {:ok, %{"id" => id, "status" => "inprocess"}}
      end
    end)

    run()
    assert status(fine) == :in_production
    assert status(broken) == :submitted
  end

  test "a rate limit and a missing order are tolerated" do
    member = member_fixture()
    a = purchase_order_fixture(member, :submitted)
    b = purchase_order_fixture(member, :submitted)

    stub(ClientMock, :get_order, fn id ->
      if id == a.printful_order_id,
        do:
          {:error,
           %Error{type: :rate_limited, status: 429, message: "slow down"}},
        else: {:error, %Error{type: :not_found, status: 404, message: "gone"}}
    end)

    run()
    assert status(a) == :submitted
    assert status(b) == :submitted
  end
end
