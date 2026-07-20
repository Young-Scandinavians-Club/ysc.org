defmodule Ysc.Media.ImageOpsTest do
  use ExUnit.Case, async: true

  alias Ysc.Media.ImageOps

  @fixture_path Path.expand("../../support/fixtures/tiny.png", __DIR__)

  describe "blur_hash_from_path/3" do
    test "returns a valid blurhash string for a PNG fixture" do
      assert {:ok, hash} = ImageOps.blur_hash_from_path(@fixture_path, 4, 3)
      assert is_binary(hash)
      assert String.length(hash) > 6
      assert String.match?(hash, ~r/^[0-9A-Za-z#$%*+,\-.:;=?@\[\]^_{|}~]+$/)
    end

    test "returns error for a missing file" do
      assert {:error, _} =
               ImageOps.blur_hash_from_path(
                 "/tmp/nonexistent-#{System.unique_integer()}.png",
                 4,
                 3
               )
    end
  end
end
