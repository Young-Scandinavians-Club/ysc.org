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

  defp trans(fun), do: :global.trans(@lock, fun, [Node.self()], :infinity)
end
