defmodule QueryConsole.Runner.LeaseTest do
  use QueryConsole.DataCase, async: false

  alias QueryConsole.Runner.{Lease, QueryRun}
  alias QueryConsole.Repo

  test "acquire and release global lease" do
    user = user_fixture()

    {:ok, run} =
      %QueryRun{}
      |> QueryRun.changeset(%{
        user_id: user.id,
        status: "queued",
        mode: "all",
        statement_count: 1
      })
      |> Repo.insert()

    assert {:ok, lease} = Lease.acquire(run.id)
    assert lease.query_run_id == run.id
    assert Lease.held?()

    assert {:error, :lease_held} = Lease.acquire(run.id)

    assert :ok = Lease.release(run.id)
    refute Lease.held?()

    assert {:ok, _} = Lease.acquire(run.id)
    assert :ok = Lease.release_holder()
    refute Lease.held?()
  end
end
