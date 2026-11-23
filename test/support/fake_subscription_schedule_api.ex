defmodule Ysc.FakeSubscriptionScheduleApi do
  @moduledoc """
  Stand-in for `Stripe.SubscriptionSchedule`.

  Same-process tests use the process dictionary and `send(self())` (default).
  LiveView tests call `start_agent/0` so a different process can record calls
  and return configured results:

      start_agent()
      put_result(:update, error)
      calls()
  """

  @agent_env :stripe_schedule_api_agent

  def start_agent do
    stop_agent()
    {:ok, pid} = Agent.start_link(fn -> %{results: %{}, calls: []} end)
    Application.put_env(:ysc, @agent_env, pid)
    pid
  end

  def stop_agent do
    case Application.get_env(:ysc, @agent_env) do
      pid when is_pid(pid) ->
        if Process.alive?(pid), do: Agent.stop(pid)
        Application.delete_env(:ysc, @agent_env)

      _ ->
        Application.delete_env(:ysc, @agent_env)
    end

    :ok
  end

  def put_result(fun, result) do
    case agent_pid() do
      pid when is_pid(pid) ->
        Agent.update(pid, fn state ->
          %{state | results: Map.put(state.results, fun, result)}
        end)

      _ ->
        Process.put({__MODULE__, fun}, result)
    end
  end

  def calls do
    case agent_pid() do
      pid when is_pid(pid) -> Agent.get(pid, & &1.calls)
      _ -> []
    end
  end

  def create(params), do: record(:create, [params])
  def update(id, params), do: record(:update, [id, params])
  def retrieve(id), do: record(:retrieve, [id])
  def cancel(id), do: record(:cancel, [id])
  def release(id), do: record(:release, [id])
  def list(params), do: record(:list, [params])

  defp record(fun, args) do
    case agent_pid() do
      pid when is_pid(pid) ->
        Agent.get_and_update(pid, fn state ->
          result = Map.get(state.results, fun, default_result(fun))

          {result, %{state | calls: state.calls ++ [{fun, args}]}}
        end)

      _ ->
        send(self(), {fun, args})
        Process.get({__MODULE__, fun}, default_result(fun))
    end
  end

  defp default_result(:list), do: {:ok, %{data: []}}
  defp default_result(_fun), do: {:ok, %{id: "sub_sched_fake"}}

  defp agent_pid do
    case Application.get_env(:ysc, @agent_env) do
      pid when is_pid(pid) ->
        if Process.alive?(pid), do: pid

      _ ->
        nil
    end
  end
end
