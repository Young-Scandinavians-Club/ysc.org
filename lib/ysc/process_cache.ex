defmodule Ysc.ProcessCache do
  @moduledoc """
  Toggle for process-global Cachex-backed caches.

  Disabled in test because Ecto SQL Sandbox isolates database state per test,
  but Cachex entries are shared across concurrent ExUnit cases.
  """

  @doc false
  def enabled? do
    Application.get_env(:ysc, :process_caches_enabled, true)
  end
end
