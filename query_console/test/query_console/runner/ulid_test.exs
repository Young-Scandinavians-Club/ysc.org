defmodule QueryConsole.Postgrex.ULIDTest do
  use QueryConsole.DataCase, async: false

  alias QueryConsole.AnalyticsRepo

  test "AnalyticsRepo decodes uuid columns as Crockford ULID strings" do
    ulid = Ecto.ULID.generate()

    assert {:ok, %{rows: [[decoded]]}} =
             AnalyticsRepo.query("SELECT $1::uuid", [ulid])

    assert decoded == ulid
    assert byte_size(decoded) == 26
    assert {:ok, _} = Jason.encode(%{id: decoded})
  end

  test "Cells fallback still decodes raw 16-byte ULID binaries" do
    ulid = "01KYN8QYVEVJMPCSKBPKV0S3ZZ"
    {:ok, binary} = Ecto.ULID.dump(ulid)
    assert QueryConsole.Runner.Cells.serialize(binary) == ulid
  end
end
