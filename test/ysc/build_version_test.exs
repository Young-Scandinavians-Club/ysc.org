defmodule Ysc.BuildVersionTest do
  use ExUnit.Case, async: true

  alias Ysc.BuildVersion

  describe "version/0" do
    test "returns a version string" do
      version = BuildVersion.version()
      assert is_binary(version)
      assert version != ""
    end
  end
end
