defmodule Ysc.EmailValidatorTestHelper do
  @moduledoc """
  Helpers for controlling MX validation in tests without real DNS lookups.

  Prefer `stub_mx_no_records/0` and `stub_mx_ok/0` over random nonexistent domains.
  Use `with_real_mx_lookup/1` only for optional `@tag :external_dns` integration tests.
  """

  alias Ysc.Newsletter.EmailValidator

  @process_mx_override_key {EmailValidator, :process_mx_override}

  @doc """
  Stubs MX resolution to succeed (process-local; use in the same process as validation).
  """
  def stub_mx_ok do
    Process.put(@process_mx_override_key, fn _domain -> :ok end)

    ExUnit.Callbacks.on_exit(fn ->
      Process.delete(@process_mx_override_key)
    end)

    :ok
  end

  @doc """
  Stubs MX resolution to return `{:error, :no_mx_records}` via Application env.

  Works across processes (e.g. LiveView newsletter signup tests).
  """
  def stub_mx_no_records do
    put_application_mx_resolver(fn _domain -> {:error, :no_mx_records} end)
  end

  @doc """
  Stubs MX resolution via Application env (visible to all processes in this test).
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

    Process.delete(@process_mx_override_key)

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

      case prev_app do
        nil -> Application.delete_env(:ysc, EmailValidator)
        env -> Application.put_env(:ysc, EmailValidator, env)
      end
    end
  end
end
