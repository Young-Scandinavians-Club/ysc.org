defmodule Ysc.Test.AuthRateLimitHelper do
  @moduledoc """
  Serializes temporary changes to process-global `:ysc, Ysc.AuthRateLimit`.

  `Ysc.AuthRateLimit` re-reads `ip_limit` / `identifier_limit` on every check.
  Tests that lower those values in `setup` can race with another test's
  `on_exit` restoring the high test defaults (see `Ysc.Test.GlobalLock`), so a
  later attempt is allowed instead of rate-limited.
  """

  alias Ysc.AuthRateLimit

  @lock {:ysc_test_auth_rate_limit, :lock}

  @doc """
  Acquires the global lock and sets AuthRateLimit env. Pair with
  `restore!/1` in `on_exit` — the lock isn't released until then, so it
  covers the whole test body in between. Held by a dedicated process
  (see `Ysc.Test.GlobalLock`), since the test process itself may exit
  before `on_exit` runs.
  """
  def capture!(opts) when is_list(opts) do
    owner = Ysc.Test.GlobalLock.acquire!(@lock)
    original = Application.get_env(:ysc, AuthRateLimit)
    Application.put_env(:ysc, AuthRateLimit, opts)
    {owner, original}
  end

  @doc """
  Restores the original value and releases the lock acquired by `capture!/1`.
  """
  def restore!({owner, original}) do
    Ysc.Test.GlobalLock.release!(owner, fn -> restore(original) end)
  end

  defp restore(nil), do: Application.delete_env(:ysc, AuthRateLimit)
  defp restore(value), do: Application.put_env(:ysc, AuthRateLimit, value)
end
