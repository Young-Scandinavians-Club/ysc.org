defmodule Ysc.Test.EnvHelper do
  @moduledoc """
  Serializes temporary changes to process-global `:ysc, :environment`.

  Async suites override this application env. Use `with_environment/2` for tests
  that need a non-default env for their whole body so parallel setup resets
  cannot clobber them mid-test.
  """

  @lock {:ysc_test_env, :lock}

  @doc false
  def reset_environment! do
    trans(fn ->
      Application.put_env(:ysc, :environment, "test")
    end)
  end

  @doc """
  Acquires the global lock and sets `:ysc, :environment` to `value`, returning
  the prior value. The lock is held until `restore_environment!/1` releases
  it, so it spans the whole test body (not just this call) — required
  because code under test re-reads `Application.get_env` at call time, not
  just at the moment this sets it.

  Pair with `restore_environment!/1` in `on_exit` when a whole test needs a non-default env.
  """
  def capture_environment!(value) do
    :global.set_lock(@lock, [Node.self()], :infinity)
    original = Application.get_env(:ysc, :environment)
    Application.put_env(:ysc, :environment, value)
    original
  end

  @doc """
  Runs `fun` while `:ysc, :environment` is set to `value`, then restores it.
  """
  def with_environment(value, fun) when is_function(fun, 0) do
    trans(fn ->
      original = Application.get_env(:ysc, :environment)

      try do
        Application.put_env(:ysc, :environment, value)
        fun.()
      after
        restore(original)
      end
    end)
  end

  defp restore(nil), do: Application.delete_env(:ysc, :environment)
  defp restore(value), do: Application.put_env(:ysc, :environment, value)

  @doc """
  Restores the original value and releases the lock acquired by
  `capture_environment!/1`.
  """
  def restore_environment!(original) do
    restore(original)
    :global.del_lock(@lock, [Node.self()])
  end

  defp trans(fun), do: :global.trans(@lock, fun, [Node.self()], :infinity)
end
