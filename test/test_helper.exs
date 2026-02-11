ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Ysc.Repo, :manual)

# Suppress DBConnection "owner/client exited" logs in test. These are normal when
# each test's sandbox owner process exits; they are not failures.
Logger.put_application_level(:db_connection, :none)

# Note: Application logging uses Ysc.Logging which skips Sentry integration in test
# but still emits logs for test verification purposes.
