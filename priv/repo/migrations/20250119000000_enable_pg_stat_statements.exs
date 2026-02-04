defmodule Ysc.Repo.Migrations.EnablePgStatStatements do
  use Ecto.Migration

  def change do
    execute(
      """
      DO $$
      BEGIN
        CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
      EXCEPTION
        WHEN OTHERS THEN
          -- Extension not available (e.g., on Fly.io), silently skip
          NULL;
      END $$;
      """,
      ""
    )
  end
end
