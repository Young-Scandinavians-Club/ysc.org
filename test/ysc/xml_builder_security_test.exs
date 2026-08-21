defmodule Ysc.XmlBuilderSecurityTest do
  use ExUnit.Case, async: true

  describe "EEF-CVE-2026-47079 entity escaping" do
    test "escapes entity-like sequences so XML parsers do not promote them to markup" do
      xml =
        XmlBuilder.generate(
          {:title, nil, "&lt;script&gt;alert(1)&lt;/script&gt;"}
        )

      assert xml =~ "&amp;lt;script&amp;gt;alert(1)&amp;lt;/script&amp;gt;"
      refute xml =~ "&lt;script&gt;"
    end

    test "escapes ampersands in attribute values even when they look like entities" do
      xml = XmlBuilder.generate({:link, %{title: "A &lt; B"}, nil})

      assert xml =~ ~s|title="A &amp;lt; B"|
    end
  end

  describe "EEF-CVE-2026-47080 CDATA breakout" do
    test "splits ]]> inside CDATA so it cannot close the section early" do
      xml = XmlBuilder.generate({:body, nil, {:cdata, "safe]]>injected"}})

      assert xml =~ "<![CDATA[safe]]]]><![CDATA[>injected]]>"
      refute xml =~ "<![CDATA[safe]]>injected]]>"
    end
  end

  describe "EEF-CVE-2026-48590 name sanitization" do
    test "raises when an element name would break out of the tag" do
      assert_raise XmlBuilder.SanitizationError, fn ->
        XmlBuilder.generate({"foo><bar", nil, "x"})
      end
    end

    test "raises when an attribute name contains structural characters" do
      assert_raise XmlBuilder.SanitizationError, fn ->
        XmlBuilder.generate({:item, %{"a\" onclick": "evil"}, "x"})
      end
    end
  end
end
