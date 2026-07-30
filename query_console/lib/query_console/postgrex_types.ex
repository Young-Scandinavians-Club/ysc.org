Postgrex.Types.define(
  QueryConsole.PostgrexTypes,
  [QueryConsole.Postgrex.ULID] ++ Ecto.Adapters.Postgres.extensions(),
  json: Jason
)
