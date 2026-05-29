defmodule Ysc.EmailValidatorTestHelper do
  @moduledoc """
  Helpers for controlling MX validation in tests without real DNS lookups.

  Prefer `stub_mx_no_records/0` or `stub_mx_no_records/1` (with a LiveView) over
  random nonexistent domains. Use `with_real_mx_lookup/1` only for optional
  `@tag :external_dns` integration tests.
  """

  alias Ysc.Newsletter.EmailValidator

  @mx_overrides_table :ysc_mx_test_overrides
  @process_mx_override_key {EmailValidator, :process_mx_override}

  @doc """
  Stubs MX resolution to succeed in the current process (or the given pid / LiveView).
  """
  def stub_mx_ok(target \\ self()) do
    put_mx_override(target, fn _domain -> :ok end)
  end

  @doc """
  Stubs MX resolution to return `{:error, :no_mx_records}`.

  Pass a `Phoenix.LiveViewTest` view (or its pid) when validation runs in a LiveView
  process; omit the argument when validation runs in the test process.
  """
  def stub_mx_no_records(target \\ self()) do
    put_mx_override(target, fn _domain -> {:error, :no_mx_records} end)
  end

  @doc """
  Stubs MX resolution for a specific process via ETS (async-safe; no Application env).
  """
  def put_mx_override(target, fun) when is_function(fun, 1) do
    pid = resolve_mx_override_pid(target)

    :ets.insert(@mx_overrides_table, {pid, fun})

    ExUnit.Callbacks.on_exit(fn ->
      :ets.delete(@mx_overrides_table, pid)
    end)

    :ok
  end

  @doc """
  Stubs MX resolution via Application env (global; avoid in `async: true` tests).
  """
  def put_application_mx_resolver(fun) when is_function(fun, 1) do
    prev = Application.get_env(:ysc, EmailValidator)

    Application.put_env(
      :ysc,
      EmailValidator,
      Keyword.put(prev || [], :mx_resolver, fun)
    )

    ExUnit.Callbacks.on_exit(fn ->
      case prev do
        nil -> Application.delete_env(:ysc, EmailValidator)
        env -> Application.put_env(:ysc, EmailValidator, env)
      end
    end)

    :ok
  end

  @doc """
  Runs `fun` with real `:inet_res` MX lookups (no Application or process overrides).
  """
  def with_real_mx_lookup(fun) when is_function(fun, 0) do
    prev_app = Application.get_env(:ysc, EmailValidator)
    prev_proc = Process.get(@process_mx_override_key)
    test_pid = self()
    prev_ets = :ets.lookup(@mx_overrides_table, test_pid)

    Process.delete(@process_mx_override_key)
    :ets.delete(@mx_overrides_table, test_pid)

    case prev_app do
      nil ->
        Application.delete_env(:ysc, EmailValidator)

      kw when is_list(kw) ->
        kw_without = Keyword.delete(kw, :mx_resolver)

        if kw_without == [] do
          Application.delete_env(:ysc, EmailValidator)
        else
          Application.put_env(:ysc, EmailValidator, kw_without)
        end
    end

    try do
      fun.()
    after
      case prev_proc do
        nil -> Process.delete(@process_mx_override_key)
        val -> Process.put(@process_mx_override_key, val)
      end

      case prev_ets do
        [] -> :ok
        [{^test_pid, fun}] -> :ets.insert(@mx_overrides_table, {test_pid, fun})
      end

      case prev_app do
        nil -> Application.delete_env(:ysc, EmailValidator)
        env -> Application.put_env(:ysc, EmailValidator, env)
      end
    end
  end

  defp resolve_mx_override_pid(%Phoenix.LiveViewTest.View{pid: pid}), do: pid
  defp resolve_mx_override_pid(pid) when is_pid(pid), do: pid
end
