defmodule QueryConsole.Runner.UlidRewriteTest do
  use ExUnit.Case, async: true

  alias QueryConsole.Runner.UlidRewrite

  @ulid "01KYD3B3W65DBZYT7TXQXM1QCR"
  @ulid2 "01KYD3B3W65DBZYT7TXQXM1QCS"
  @uuid "019f9a35-8f86-2b57-ff68-faedfb40dd98"
  @uuid_cols MapSet.new(["user_id", "id"])

  describe "rewrite/2 with explicit ::uuid cast" do
    test "converts a cast literal regardless of schema" do
      sql = "SELECT '#{@ulid}'::uuid"
      assert UlidRewrite.rewrite(sql, MapSet.new()) == "SELECT '#{@uuid}'::uuid"
    end

    test "converts a CAST(... AS uuid) literal" do
      sql = "SELECT CAST('#{@ulid}' AS uuid)"
      assert UlidRewrite.rewrite(sql, MapSet.new()) == "SELECT CAST('#{@uuid}' AS uuid)"
    end
  end

  describe "rewrite/2 with a known uuid column" do
    test "converts a literal compared with =" do
      sql = "SELECT * FROM user_events WHERE user_events.user_id = '#{@ulid}' ORDER BY id DESC"

      assert UlidRewrite.rewrite(sql, @uuid_cols) ==
               "SELECT * FROM user_events WHERE user_events.user_id = '#{@uuid}' ORDER BY id DESC"
    end

    test "converts a literal on the left-hand side of the comparison" do
      sql = "SELECT * FROM user_events WHERE '#{@ulid}' = user_id"

      assert UlidRewrite.rewrite(sql, @uuid_cols) ==
               "SELECT * FROM user_events WHERE '#{@uuid}' = user_id"
    end

    test "converts every literal in an IN list" do
      sql = "SELECT * FROM t WHERE t.user_id IN ('#{@ulid}', '#{@ulid2}')"
      rewritten = UlidRewrite.rewrite(sql, @uuid_cols)

      assert rewritten =~ @uuid
      refute rewritten =~ @ulid
      refute rewritten =~ @ulid2
    end

    test "converts <> and != comparisons" do
      assert UlidRewrite.rewrite("SELECT * FROM t WHERE t.user_id <> '#{@ulid}'", @uuid_cols) =~
               @uuid

      assert UlidRewrite.rewrite("SELECT * FROM t WHERE t.user_id != '#{@ulid}'", @uuid_cols) =~
               @uuid
    end

    test "leaves an unqualified column match untouched when no column matches" do
      sql = "SELECT * FROM t WHERE t.other_id = '#{@ulid}'"
      assert UlidRewrite.rewrite(sql, @uuid_cols) == sql
    end
  end

  describe "rewrite/2 does not touch unrelated ULID-shaped literals" do
    test "leaves a literal compared to a non-uuid column alone" do
      sql = "SELECT * FROM coupons WHERE coupons.code = '#{@ulid}'"
      assert UlidRewrite.rewrite(sql, @uuid_cols) == sql
    end

    test "leaves a bare selected literal alone" do
      sql = "SELECT '#{@ulid}' AS code"
      assert UlidRewrite.rewrite(sql, @uuid_cols) == sql
    end

    test "leaves a literal in an unsupported comparison alone" do
      sql = "SELECT * FROM t WHERE t.user_id > '#{@ulid}'"
      assert UlidRewrite.rewrite(sql, @uuid_cols) == sql
    end
  end

  describe "rewrite/2 robustness" do
    test "leaves invalid SQL unchanged" do
      assert UlidRewrite.rewrite("SELECT FROM", @uuid_cols) == "SELECT FROM"
    end

    test "leaves a non-ULID 26-char literal unchanged (invalid Crockford chars)" do
      # contains 'I', 'L', 'O', 'U' which aren't in the Crockford alphabet
      sql = "SELECT * FROM t WHERE t.user_id = 'ILOU3B3W65DBZYT7TXQXM1QCR'"
      assert UlidRewrite.rewrite(sql, @uuid_cols) == sql
    end

    test "rewrites multiple statements independently" do
      sql = "SELECT '#{@ulid}'::uuid; SELECT '#{@ulid2}'::uuid"
      rewritten = UlidRewrite.rewrite(sql, MapSet.new())
      assert rewritten =~ @uuid
      assert rewritten =~ "019f9a35-8f86-2b57-ff68-faedfb40dd99"
    end
  end
end
