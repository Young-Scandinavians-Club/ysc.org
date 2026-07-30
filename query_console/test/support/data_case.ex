defmodule QueryConsole.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias QueryConsole.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import QueryConsole.DataCase
      import QueryConsole.Fixtures
    end
  end

  setup tags do
    QueryConsole.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(QueryConsole.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    # Analytics repo may point at ysc_test; sandbox it when available
    try do
      analytics_pid =
        Ecto.Adapters.SQL.Sandbox.start_owner!(QueryConsole.AnalyticsRepo,
          shared: not tags[:async]
        )

      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(analytics_pid) end)
    rescue
      _ -> :ok
    end
  end

  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
