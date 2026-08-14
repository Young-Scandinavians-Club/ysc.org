defmodule Ysc.ScanRateLimitTest do
  # Hammer ETS state is shared across processes; keep this module serial.
  use ExUnit.Case, async: false

  describe "check/1" do
    test "allows requests within the configured limit" do
      id = "scan-test-#{System.unique_integer([:positive])}"
      assert Ysc.ScanRateLimit.check(id) == :ok
    end

    test "returns rate_limited once the limit is exceeded" do
      id = "scan-overflow-#{System.unique_integer([:positive])}"

      for _ <- 1..20 do
        assert Ysc.ScanRateLimit.check(id) == :ok
      end

      assert Ysc.ScanRateLimit.check(id) == :rate_limited
    end

    test "returns rate_limited for non-binary identifiers" do
      assert Ysc.ScanRateLimit.check(123) == :rate_limited
    end
  end
end
