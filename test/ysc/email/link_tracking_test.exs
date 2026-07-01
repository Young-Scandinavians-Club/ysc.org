defmodule Ysc.Email.LinkTrackingTest do
  use ExUnit.Case, async: true

  alias Ysc.Email.LinkTracking

  describe "enabled_for_template?/1" do
    test "returns true for newsletter category templates" do
      assert LinkTracking.enabled_for_template?("newsletter_edition")
      assert LinkTracking.enabled_for_template?(:newsletter_edition)
    end

    test "returns false for account and event templates" do
      refute LinkTracking.enabled_for_template?("reset_password")
      refute LinkTracking.enabled_for_template?("newsletter_stats_snapshot")
      refute LinkTracking.enabled_for_template?("event_notification")
    end

    test "returns false for nil and unknown templates" do
      refute LinkTracking.enabled_for_template?(nil)
      refute LinkTracking.enabled_for_template?("unknown_template")
    end
  end

  describe "disable_tracking/1" do
    test "adds ses:no-track to anchor tags" do
      html = ~s(<p>Hello <a href="https://example.com">click</a></p>)

      result = LinkTracking.disable_tracking(html)

      assert result =~ ~s(href="https://example.com")
      assert result =~ "ses:no-track"
    end

    test "adds ses:no-track to multiple anchors including mj-button style" do
      html = """
      <a href="https://example.com/reset" style="display:inline-block;padding:15px">Reset</a>
      <a href="mailto:info@ysc.org">Email us</a>
      """

      result = LinkTracking.disable_tracking(html)

      assert result =~ ~s(href="https://example.com/reset")
      assert result =~ ~s(href="mailto:info@ysc.org")
      assert result =~ "ses:no-track"
      assert result |> String.split("ses:no-track") |> length() == 3
    end

    test "is idempotent when ses:no-track is already present" do
      html = ~s(<a href="https://example.com" ses:no-track>tracked off</a>)

      result = LinkTracking.disable_tracking(html)

      assert {:ok, document} = Floki.parse_fragment(result)
      assert length(Floki.find(document, "a")) == 1
    end

    test "leaves non-anchor tags unchanged" do
      html = ~s(<div><img src="x.png"><span>text</span></div>)

      result = LinkTracking.disable_tracking(html)

      refute result =~ "ses:no-track"
      assert result =~ ~s(<img src="x.png")
      assert result =~ "<span>text</span>"
    end

    test "returns empty string for nil and empty input" do
      assert LinkTracking.disable_tracking(nil) == ""
      assert LinkTracking.disable_tracking("") == ""
    end
  end
end
