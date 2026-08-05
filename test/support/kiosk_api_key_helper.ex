defmodule Ysc.Test.KioskAPIKeyHelper do
  @moduledoc """
  Serializes temporary changes to process-global `:ysc, :kiosk_api_key`.

  `MobileAPIAuth` re-reads this config on every request, so a value set in
  `setup` stays live for the whole test body, not just the moment it's
  written. `capture_kiosk_api_key!/1` + `restore_kiosk_api_key!/1` (the usual
  setup/on_exit pairing) must therefore hold the lock across the entire test,
  not just around each mutation — otherwise a concurrent async test can swap
  the key mid-request and this one gets a false "Invalid authorization token".
  Use `:global.set_lock/del_lock` (not `trans/2`, which only wraps a single
  call) to actually span that gap.
  """

  @lock {:ysc_test_kiosk_api_key, :lock}

  @doc """
  Acquires the global lock and sets `:ysc, :kiosk_api_key`. Pair with
  `restore_kiosk_api_key!/1` in `on_exit` — the lock isn't released until
  then, so it covers the whole test body in between. Held by a dedicated
  process (see `Ysc.Test.GlobalLock`), since the test process itself may
  exit before `on_exit` runs.
  """
  def capture_kiosk_api_key!(value) do
    owner = Ysc.Test.GlobalLock.acquire!(@lock)
    original = Application.get_env(:ysc, :kiosk_api_key)
    Application.put_env(:ysc, :kiosk_api_key, value)
    {owner, original}
  end

  @doc """
  Restores the original value and releases the lock acquired by
  `capture_kiosk_api_key!/1`.
  """
  def restore_kiosk_api_key!({owner, original}) do
    Ysc.Test.GlobalLock.release!(owner, fn -> restore(original) end)
  end

  @doc """
  Runs `fun` while `:ysc, :kiosk_api_key` is set to `value`, holding the lock
  for the duration, then restores it.
  """
  def with_kiosk_api_key(value, fun) when is_function(fun, 0) do
    trans(fn ->
      original = Application.get_env(:ysc, :kiosk_api_key)

      try do
        Application.put_env(:ysc, :kiosk_api_key, value)
        fun.()
      after
        restore(original)
      end
    end)
  end

  defp restore(nil), do: Application.delete_env(:ysc, :kiosk_api_key)
  defp restore(value), do: Application.put_env(:ysc, :kiosk_api_key, value)

  defp trans(fun), do: :global.trans(@lock, fun, [Node.self()], :infinity)
end
