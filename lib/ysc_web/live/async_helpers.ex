defmodule YscWeb.Live.AsyncHelpers do
  @moduledoc """
  Helper functions for LiveView async operations that need database access.

  In test environment, async tasks spawned with Task.async_stream need explicit
  permission to access the Ecto SQL Sandbox. This module provides helpers to
  automatically handle sandbox allowance.

  ## Usage

  In your LiveView:

      import YscWeb.Live.AsyncHelpers

      # Use async_stream_with_repo instead of Task.async_stream
      results =
        tasks
        |> async_stream_with_repo(fn {key, fun} -> {key, fun.()} end)
        |> Enum.reduce(%{}, fn {:ok, {key, value}}, acc -> Map.put(acc, key, value) end)

  This ensures that each spawned task has proper sandbox access in tests.
  """

  @doc """
  Wraps Task.async_stream to automatically allow sandbox access in test environment.

  This function should be used instead of Task.async_stream when the tasks need
  to access the database via Ecto.

  ## Options

  All options from Task.async_stream are supported and passed through.
  """
  def async_stream_with_repo(enumerable, fun, opts \\ []) do
    # Get the current process (parent of tasks) for sandbox allowance
    parent = self()

    # Wrap the function to allow sandbox access
    wrapped_fun = fn item ->
      allow_sandbox_access(parent)
      fun.(item)
    end

    Task.async_stream(enumerable, wrapped_fun, opts)
  end

  @doc """
  Allows the current process to access the SQL Sandbox.

  This should be called at the beginning of any async task that needs database access.
  In production, this is a no-op.
  """
  def allow_sandbox_access(owner_pid \\ self()) do
    if Application.get_env(:ysc, :sql_sandbox) do
      try do
        Ecto.Adapters.SQL.Sandbox.allow(Ysc.Repo, self(), owner_pid)
      rescue
        # If sandbox is not active or already allowed, ignore
        _ -> :ok
      end
    end
  end
end
