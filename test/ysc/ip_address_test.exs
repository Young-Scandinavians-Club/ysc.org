defmodule Ysc.IpAddressTest do
  use ExUnit.Case, async: true

  alias Ysc.IpAddress

  describe "normalize/1" do
    test "returns canonical IPv4 text" do
      assert IpAddress.normalize(" 203.0.113.1 ") == "203.0.113.1"
    end

    test "converts IPv4-mapped IPv6 to IPv4" do
      assert IpAddress.normalize("::ffff:203.0.113.1") == "203.0.113.1"
    end

    test "returns canonical IPv6 text" do
      ip = "2607:fb90:8e93:2ba1:ac39:6d57:509c:f8ac"

      assert IpAddress.normalize(ip) == ip
    end

    test "returns nil for blank input" do
      assert IpAddress.normalize(nil) == nil
      assert IpAddress.normalize("") == nil
      assert IpAddress.normalize("   ") == nil
    end

    test "returns original text when parsing fails" do
      assert IpAddress.normalize("not-an-ip") == "not-an-ip"
    end
  end

  describe "mask/1" do
    test "masks IPv4 addresses" do
      assert IpAddress.mask("203.0.113.1") == "203.0.xxx.xxx"
    end

    test "masks IPv6 addresses" do
      ip = "2607:fb90:8e93:2ba1:ac39:6d57:509c:f8ac"
      assert IpAddress.mask(ip) == "2607:fb90:xxxx:..."
    end

    test "returns nil for blank or invalid values" do
      assert IpAddress.mask(nil) == nil
      assert IpAddress.mask("") == nil
      assert IpAddress.mask("not-an-ip") == nil
    end
  end
end
