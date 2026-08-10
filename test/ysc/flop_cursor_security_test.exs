defmodule Ysc.FlopCursorSecurityTest do
  use ExUnit.Case, async: true

  alias Flop.Cursor

  describe "decode/1 cursor hardening (flop 0.26.6+)" do
    test "rejects cursors larger than the default 8 KB limit" do
      oversized = String.duplicate("A", 8_193)

      assert Cursor.decode(oversized) == :error
    end

    test "rejects cursors containing compressed Erlang terms" do
      # 131 = version tag, 80 = zlib-compressed term tag (see Erlang external term format)
      compressed = Base.url_encode64(<<131, 80, 1, 2, 3>>)

      assert Cursor.decode(compressed) == :error
    end

    test "accepts a valid encoded cursor within size limits" do
      cursor = Cursor.encode(%{id: 1})

      assert {:ok, %{id: 1}} = Cursor.decode(cursor)
    end
  end
end
