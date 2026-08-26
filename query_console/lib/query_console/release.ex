defmodule QueryConsole.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :query_console

  # Fly Postgres (especially sandbox) can still be in recovery when the
  # release_command Machine starts. DBConnection drops checkouts after ~6s,
  # which is shorter than a typical autostart. Retry transient errors instead
  # of failing the deploy.
  @migrate_attempts 15
  @migrate_retry_delay_ms 2_000

  @transient_postgres_codes [
    :cannot_connect_now,
    :admin_shutdown,
    :crash_shutdown,
    :too_many_connections
  ]

  def migrate(opts \\ []) do
    load_app()

    attempts = Keyword.get(opts, :attempts, @migrate_attempts)
    delay_ms = Keyword.get(opts, :delay_ms, @migrate_retry_delay_ms)
    sleep = Keyword.get(opts, :sleep, &Process.sleep/1)
    migrator = Keyword.get(opts, :migrator, &run_migrations/1)

    for repo <- repos() do
      retry_transient_db(fn -> migrator.(repo) end, attempts, delay_ms, sleep)
    end

    :ok
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp run_migrations(repo) do
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
  end

  defp retry_transient_db(fun, attempts_left, delay_ms, sleep) do
    fun.()
  rescue
    e ->
      if attempts_left > 1 and transient_db_error?(e) do
        remaining = attempts_left - 1

        IO.puts(
          "Database not ready (#{exception_text(e)}); retrying in #{delay_ms}ms (#{remaining} attempts left)"
        )

        sleep.(delay_ms)
        retry_transient_db(fun, remaining, delay_ms, sleep)
      else
        reraise e, __STACKTRACE__
      end
  end

  defp transient_db_error?(%DBConnection.ConnectionError{}), do: true

  defp transient_db_error?(%Postgrex.Error{postgres: %{code: code}})
       when code in @transient_postgres_codes,
       do: true

  defp transient_db_error?(_), do: false

  defp exception_text(e) do
    Exception.message(e)
  rescue
    _ -> inspect(e)
  end

  defp repos do
    # Only migrate the metadata repo; AnalyticsRepo is read-only.
    [QueryConsole.Repo]
  end

  defp load_app do
    Application.load(@app)
  end
end
