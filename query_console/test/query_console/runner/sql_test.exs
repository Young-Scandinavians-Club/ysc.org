defmodule QueryConsole.Runner.SQLTest do
  use ExUnit.Case, async: true

  alias QueryConsole.Runner.SQL

  describe "split_statements/1" do
    test "splits multiple statements" do
      assert {:ok, stmts} = SQL.split_statements("SELECT 1; SELECT 2;")
      assert length(stmts) == 2
      assert Enum.at(stmts, 0).sql =~ "SELECT 1"
      assert Enum.at(stmts, 1).sql =~ "SELECT 2"
    end

    test "returns empty list for blank SQL" do
      assert {:ok, []} = SQL.split_statements("   ")
    end

    test "returns parse error for invalid SQL" do
      assert {:error, {:parse_error, _}} = SQL.split_statements("SELECT FROM")
    end
  end

  describe "preflight/1" do
    test "allows SELECT" do
      {:ok, stmts} = SQL.split_statements("SELECT 1")
      assert :ok = SQL.preflight(stmts)
    end

    test "rejects INSERT" do
      {:ok, stmts} = SQL.split_statements("INSERT INTO users(id) VALUES (1)")
      assert {:error, {:write_rejected, message}} = SQL.preflight(stmts)
      assert message =~ "not read-only"
    end

    test "rejects UPDATE" do
      {:ok, stmts} = SQL.split_statements("UPDATE users SET name = 'x'")
      assert {:error, {:write_rejected, _}} = SQL.preflight(stmts)
    end

    test "rejects DELETE" do
      {:ok, stmts} = SQL.split_statements("DELETE FROM users")
      assert {:error, {:write_rejected, _}} = SQL.preflight(stmts)
    end

    test "rejects CREATE TABLE" do
      {:ok, stmts} = SQL.split_statements("CREATE TABLE t (id int)")
      assert {:error, {:write_rejected, _}} = SQL.preflight(stmts)
    end

    test "rejects DROP" do
      {:ok, stmts} = SQL.split_statements("DROP TABLE users")
      assert {:error, {:write_rejected, _}} = SQL.preflight(stmts)
    end

    test "rejects COPY" do
      {:ok, stmts} = SQL.split_statements("COPY users TO STDOUT")
      assert {:error, {:write_rejected, _}} = SQL.preflight(stmts)
    end

    test "rejects SELECT FOR UPDATE" do
      {:ok, stmts} = SQL.split_statements("SELECT * FROM users FOR UPDATE")
      assert {:error, {:write_rejected, message}} = SQL.preflight(stmts)
      assert message =~ "FOR UPDATE"
    end
  end
end
