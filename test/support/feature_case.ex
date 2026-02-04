defmodule YscWeb.FeatureCase do
  @moduledoc """
  Test support module for feature tests.

  Provides helpers and setup functions for end-to-end feature testing.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      use YscWeb, :verified_routes

      import YscWeb.FeatureCase

      import PhoenixTest
    end
  end

  setup tags do
    pid =
      Ecto.Adapters.SQL.Sandbox.start_owner!(Ysc.Repo, shared: not tags[:async])

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
