ExUnit.start(capture_log: true)
{:ok, _} = Ysc.HttpTestServer.start_link()

# Host .env may define QUICKBOOKS_*; never use those in tests (avoids Intuit HTTP).
qb_config = Application.get_env(:ysc, :quickbooks, [])

Application.put_env(
  :ysc,
  :quickbooks,
  Keyword.merge(qb_config,
    client_id: nil,
    client_secret: nil,
    company_id: nil,
    access_token: nil,
    refresh_token: nil,
    realm_id: nil,
    url: "http://127.0.0.1:1"
  )
)

Application.put_env(:ysc, :google_photos,
  client_id: "test_google_photos_client_id",
  client_secret: "test_google_photos_client_secret"
)

Ecto.Adapters.SQL.Sandbox.mode(Ysc.Repo, :manual)

# Per-process MX resolver overrides for async-safe newsletter tests (see EmailValidatorTestHelper).
:ets.new(:ysc_mx_test_overrides, [
  :named_table,
  :public,
  :set,
  read_concurrency: true
])

# Suppress noisy application loggers during tests.
for app <- [:db_connection, :phoenix, :phoenix_live_view, :ecto, :oban] do
  Ysc.Logging.put_application_level(app, :none)
end
