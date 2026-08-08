defmodule Ysc.Test.GlobalLock do
  @moduledoc """
  Holds a `:global` lock across a test's `setup`/`on_exit` gap.

  `:global.set_lock/3` ties lock ownership to the calling process: if that
  process exits, `:global` auto-releases the lock. ExUnit's `on_exit`
  callbacks run in a *different* process than the test itself, so a lock
  acquired directly by the test process (e.g. from `setup`) would already be
  released — silently, with no warning — by the time `on_exit` runs, leaving
  a window where another test can sneak in.

  `acquire!/1` spawns a dedicated process to hold the lock instead, so it
  survives the test process exiting. `release!/2` tells that process to run
  the restore and let go, then waits for it to confirm.
  """

  @doc "Spawns a process that acquires `lock_id` and blocks until told to release it."
  def acquire!(lock_id) do
    parent = self()

    owner =
      spawn(fn ->
        :global.set_lock(lock_id, [Node.self()], :infinity)
        send(parent, {:ysc_test_global_lock, self(), :locked})

        receive do
          {:release, restore_fun, from} ->
            restore_fun.()
            :global.del_lock(lock_id, [Node.self()])
            send(from, {:ysc_test_global_lock, self(), :released})
        end
      end)

    receive do
      {:ysc_test_global_lock, ^owner, :locked} -> owner
    end
  end

  @doc "Tells `owner` (from `acquire!/1`) to run `restore_fun`, release the lock, and exit."
  def release!(owner, restore_fun) do
    send(owner, {:release, restore_fun, self()})

    receive do
      {:ysc_test_global_lock, ^owner, :released} -> :ok
    end
  end
end
