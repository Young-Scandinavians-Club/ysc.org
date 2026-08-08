defmodule YscWeb.Sms.SegmentTest do
  use ExUnit.Case, async: true

  alias YscWeb.Sms.Segment

  describe "build_event_update_sms/3" do
    test "strips HTML and prefixes with [YSC]" do
      result =
        Segment.build_event_update_sms(
          "Midsummer Picnic",
          "Venue Change",
          "<p>We grabbed the <strong>tables</strong> in the back!</p>"
        )

      assert result.body ==
               "[YSC] Venue Change: We grabbed the tables in the back!"

      assert result.encoding == :gsm7
      assert result.segment_count == 1
      refute result.truncated?
      refute result.multi_segment?
    end

    test "preserves newlines and spaces from Trix HTML breaks" do
      html =
        "<div><!--block-->We are at the table in the very<strong> back of the pub!<br><br>Come and dance with us.</strong></div>"

      result =
        Segment.build_event_update_sms(
          "Scandinavian Gala Dinner",
          nil,
          html
        )

      assert result.body ==
               "[YSC] Scandinavian Gala Dinner: We are at the table in the very back of the pub!\n\nCome and dance with us."

      refute String.contains?(result.body, "pub!Come")
    end

    test "preserves paragraph breaks as newlines" do
      result =
        Segment.build_event_update_sms(
          "Picnic",
          "Update",
          "<p>First paragraph.</p><p>Second paragraph.</p>"
        )

      assert result.body ==
               "[YSC] Update: First paragraph.\nSecond paragraph."
    end

    test "falls back to event title when update title is blank" do
      result =
        Segment.build_event_update_sms("Picnic", "", "<p>Gate code is 1234</p>")

      assert result.body == "[YSC] Picnic: Gate code is 1234"
    end

    test "excludes Trix figures, images, and captions from SMS body" do
      html = """
      <div>We grabbed the tables.
      <figure>
        <a href="/uploads/photo.jpg"><img src="/uploads/photo.jpg" alt="Venue photo" /></a>
        <figcaption>Tables in the back corner</figcaption>
      </figure>
      <p>Come and dance with us.</p></div>
      """

      result =
        Segment.build_event_update_sms("Picnic", "Update", html)

      assert result.body ==
               "[YSC] Update: We grabbed the tables.\nCome and dance with us."

      refute String.contains?(result.body, "Venue photo")
      refute String.contains?(result.body, "Tables in the back corner")
      refute String.contains?(result.body, "/uploads/photo.jpg")
    end

    test "excludes standalone img tags without a figure wrapper" do
      html = ~s(<p>Hello <img src="/x.jpg" alt="skip me" /> world</p>)

      result = Segment.build_event_update_sms("Event", nil, html)

      assert result.body == "[YSC] Event: Hello world"
      refute String.contains?(result.body, "skip me")
    end

    test "uses UCS-2 encoding when non-GSM characters are present" do
      result =
        Segment.build_event_update_sms("Picnic", nil, "<p>See you 🎉</p>")

      assert result.encoding == :ucs2
      assert String.contains?(result.body, "🎉")
    end

    test "soft-caps at 2 GSM segments and marks truncated" do
      long_body = String.duplicate("a", 400)

      result = Segment.build_event_update_sms("Event", "Update", long_body)

      assert result.truncated?
      assert result.multi_segment?
      assert result.segment_count == 2
      assert result.char_count <= 306
      assert String.ends_with?(result.body, "...")
    end

    test "warns for multi-segment messages under the soft-cap" do
      # Build a body that exceeds 160 GSM chars but stays under 306
      body = String.duplicate("b", 200)

      result = Segment.build_event_update_sms("E", "T", body)

      assert result.multi_segment?
      assert result.segment_count == 2
      refute result.truncated?
    end
  end

  describe "encoding/1" do
    test "stays GSM-7 for basic latin and GSM accents" do
      assert Segment.encoding("Hej äöñüà Åå") == :gsm7
      assert Segment.encoding("Gate code is 1234!") == :gsm7
    end

    test "switches to UCS-2 for smart quotes, em dash, and non-GSM accents" do
      assert Segment.encoding("“smart quotes”") == :ucs2
      assert Segment.encoding("em—dash") == :ucs2
      assert Segment.encoding("café with á and í") == :ucs2
    end

    test "switches to UCS-2 for emoji" do
      assert Segment.encoding("See you 🎉") == :ucs2
    end
  end

  describe "unit_count/2" do
    test "counts GSM-7 basic characters as 1 septet each" do
      assert Segment.unit_count("Hello", :gsm7) == 5
      assert Segment.unit_count("a\nb", :gsm7) == 3
    end

    test "counts GSM-7 extended characters as 2 septets each" do
      assert Segment.unit_count("^", :gsm7) == 2
      assert Segment.unit_count("|", :gsm7) == 2
      assert Segment.unit_count("€", :gsm7) == 2
      assert Segment.unit_count("{}", :gsm7) == 4
      assert Segment.unit_count("[]", :gsm7) == 4
      assert Segment.unit_count("~", :gsm7) == 2
      assert Segment.unit_count("\\", :gsm7) == 2
    end

    test "counts [YSC] prefix brackets as extended GSM (7 septets total)" do
      # [ = 2, Y = 1, S = 1, C = 1, ] = 2
      assert Segment.unit_count("[YSC]", :gsm7) == 7
    end

    test "counts a single LF as 1 GSM septet after CRLF normalization" do
      analysis = Segment.analyze_and_cap("a\r\nb")
      assert analysis.body == "a\nb"
      assert analysis.encoding == :gsm7
      assert analysis.char_count == 3
    end

    test "counts UCS-2 BMP characters as 1 and emoji as 2 UTF-16 units" do
      assert Segment.unit_count("Hi", :ucs2) == 2
      # 🎉 is U+1F389 — one Unicode scalar, two UTF-16 code units
      assert Segment.unit_count("🎉", :ucs2) == 2
      assert Segment.unit_count("A🎉", :ucs2) == 3
    end
  end

  describe "segment_count/2" do
    test "GSM-7: 160 is one segment; 161 becomes two (153+8)" do
      assert Segment.segment_count(1, :gsm7) == 1
      assert Segment.segment_count(160, :gsm7) == 1
      assert Segment.segment_count(161, :gsm7) == 2
      assert Segment.segment_count(306, :gsm7) == 2
      assert Segment.segment_count(307, :gsm7) == 3
    end

    test "UCS-2: 70 is one segment; 71 becomes two (67+4)" do
      assert Segment.segment_count(70, :ucs2) == 1
      assert Segment.segment_count(71, :ucs2) == 2
      assert Segment.segment_count(134, :ucs2) == 2
      assert Segment.segment_count(135, :ucs2) == 3
    end

    test "analyze_and_cap crosses into 2 GSM segments at 161 septets" do
      # 161 basic latin characters
      body = String.duplicate("a", 161)
      analysis = Segment.analyze_and_cap(body)

      assert analysis.encoding == :gsm7
      assert analysis.char_count == 161
      assert analysis.segment_count == 2
      assert analysis.multi_segment?
      refute analysis.truncated?
    end

    test "extended characters can push a short string over 160 septets" do
      # 159 basic + one € (2) = 161 septets → 2 segments
      body = String.duplicate("a", 159) <> "€"
      analysis = Segment.analyze_and_cap(body)

      assert analysis.encoding == :gsm7
      assert analysis.char_count == 161
      assert analysis.segment_count == 2
    end

    test "one emoji forces UCS-2 70-char single-segment limit" do
      # 69 BMP chars + 1 emoji (2 units) = 71 units → 2 UCS-2 segments
      body = String.duplicate("a", 69) <> "🎉"
      analysis = Segment.analyze_and_cap(body)

      assert analysis.encoding == :ucs2
      assert analysis.char_count == 71
      assert analysis.segment_count == 2
    end
  end
end
