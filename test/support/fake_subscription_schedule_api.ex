defmodule Ysc.FakeSubscriptionScheduleApi do
  @moduledoc """
  Stand-in for `Stripe.SubscriptionSchedule` that reports each call to the
  calling process and returns the result configured under `{__MODULE__, fun}`
  in the process dictionary (default `{:ok, %{id: "sub_sched_fake"}}`).
  """

  def put_result(fun, result), do: Process.put({__MODULE__, fun}, result)

  def create(params), do: record(:create, [params])
  def update(id, params), do: record(:update, [id, params])
  def cancel(id), do: record(:cancel, [id])
  def release(id), do: record(:release, [id])

  def list(params) do
    send(self(), {:list, [params]})
    Process.get({__MODULE__, :list}, {:ok, %{data: []}})
  end

  defp record(fun, args) do
    send(self(), {fun, args})
    Process.get({__MODULE__, fun}, {:ok, %{id: "sub_sched_fake"}})
  end
end
