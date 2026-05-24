ExUnit.start()
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

Ecto.Adapters.SQL.Sandbox.mode(Ysc.Repo, :manual)

# Suppress DBConnection "owner/client exited" logs in test. These are normal when
# each test's sandbox owner process exits; they are not failures.
Logger.put_application_level(:db_connection, :none)

# Note: Application logging uses Ysc.Logging which skips Sentry integration in test
# but still emits logs for test verification purposes.
