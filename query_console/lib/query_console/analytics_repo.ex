defmodule QueryConsole.AnalyticsRepo do
  @moduledoc """
  Read-path repository for analytics/SQL execution.

  Configured with a small pool and `prepare: :unnamed` so statements can be
  cancelled and do not pin named prepared statements on pooled connections.
  """

  use Ecto.Repo,
    otp_app: :query_console,
    adapter: Ecto.Adapters.Postgres
end
