defmodule QueryConsole.Repo do
  use Ecto.Repo,
    otp_app: :query_console,
    adapter: Ecto.Adapters.Postgres
end
