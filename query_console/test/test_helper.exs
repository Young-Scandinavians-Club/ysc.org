ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(QueryConsole.Repo, :manual)

# AnalyticsRepo points at ysc_test for read-path integration checks.
try do
  Ecto.Adapters.SQL.Sandbox.mode(QueryConsole.AnalyticsRepo, :manual)
rescue
  _ -> :ok
end
