defmodule Ysc.QueryConsoleTest do
  use ExUnit.Case, async: true

  test "url/0 returns configured base without trailing slash" do
    assert Ysc.QueryConsole.url() == "http://localhost:4001"
  end

  test "host/0 returns hostname for UI copy" do
    assert Ysc.QueryConsole.host() == "localhost"
  end
end
