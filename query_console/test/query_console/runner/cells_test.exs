defmodule QueryConsole.Runner.CellsTest do
  use ExUnit.Case, async: true

  alias QueryConsole.Runner.Cells

  test "passes through UTF-8 strings and numbers" do
    assert Cells.serialize("hello") == "hello"
    assert Cells.serialize(42) == 42
    assert Cells.serialize(true) == true
    assert Cells.serialize(nil) == nil
  end

  test "passes through already-decoded ULID strings" do
    ulid = "01KYN8QYVEVJMPCSKBPKV0S3ZZ"
    assert Cells.serialize(ulid) == ulid
  end

  test "encodes binary ULIDs as Crockford strings (Jason-safe)" do
    {:ok, binary} = Ecto.ULID.dump("01KYN8QYVEVJMPCSKBPKV0S3ZZ")
    assert Cells.serialize(binary) == "01KYN8QYVEVJMPCSKBPKV0S3ZZ"
    assert {:ok, _} = Jason.encode(%{id: Cells.serialize(binary)})
  end

  test "encodes arbitrary non-UTF8 binaries as hex" do
    bin = <<0, 1, 2, 255, 9>>
    assert Cells.serialize(bin) == "\\x000102ff09"
    assert {:ok, _} = Jason.encode([Cells.serialize(bin)])
  end

  test "serializes nested lists and maps" do
    assert Cells.serialize([1, "a", nil]) == [1, "a", nil]
    assert Cells.serialize(%{"a" => 1, :b => "x"}) == %{"a" => 1, "b" => "x"}
  end
end
