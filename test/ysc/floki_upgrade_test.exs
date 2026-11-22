defmodule Ysc.FlokiUpgradeTest do
  @moduledoc """
  Guards the floki 0.38.4 → 0.38.5 upgrade.

  0.38.5 is a patch with no documented breaking changes. The built-in
  mochiweb parser tracks open-element names in a multiset so a
  non-matching end tag is rejected without scanning the stack (linear
  instead of `O(open_depth x end_tags)`); the parse tree is unchanged.
  Functional `:nth-child` / `:nth-of-type` match with remainder
  arithmetic instead of scanning `an+b` values.

  We parse with `Floki.parse_fragment/1` then `find/2`, `text/1`,
  `raw_html/1`, `traverse_and_update/2`, and `filter_out/2` (newsletter
  HTML, SES no-track, open-in-new-tab, SMS strip). We do not pass
  `:attributes_as_maps`, `:html_parser`, or `:parser_args`, and we do
  not call `find/2` on an unparsed string. extras: none.
  """
  use ExUnit.Case, async: true

  alias Ysc.Email.LinkTracking
  alias Ysc.Html.Links
  alias YscWeb.Emails.NewsletterEdition
  alias YscWeb.PlainText
  alias YscWeb.Sms.Segment

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @changelog Path.expand("../../deps/floki/CHANGELOG.md", __DIR__)
  @mochi Path.expand("../../deps/floki/src/floki_mochi_html.erl", __DIR__)
  @pseudo Path.expand(
            "../../deps/floki/lib/floki/selector/pseudo_class.ex",
            __DIR__
          )
  @finder Path.expand("../../deps/floki/lib/floki/finder.ex", __DIR__)
  @newsletter Path.expand(
                "../../lib/ysc_web/emails/newsletter_edition.ex",
                __DIR__
              )
  @link_tracking Path.expand("../../lib/ysc/email/link_tracking.ex", __DIR__)
  @links Path.expand("../../lib/ysc/html/links.ex", __DIR__)
  @plain_text Path.expand("../../lib/ysc_web/plain_text.ex", __DIR__)
  @sms Path.expand("../../lib/ysc_web/sms/segment.ex", __DIR__)

  setup_all do
    {:ok, _} = Application.ensure_all_started(:floki)
    {:module, Floki} = Code.ensure_loaded(Floki)

    {:module, Floki.HTMLParser.Mochiweb} =
      Code.ensure_loaded(Floki.HTMLParser.Mochiweb)

    {:module, Floki.Selector.PseudoClass} =
      Code.ensure_loaded(Floki.Selector.PseudoClass)

    :ok
  end

  describe "0.38.5 Hex lock and public APIs" do
    test "locks the Hex package to 0.38.5" do
      assert to_string(Application.spec(:floki, :vsn)) == "0.38.5"
    end

    test "mix.exs pins the 0.38.5 floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s|{:floki, "~> 0.38.5"}|
      refute mix_exs =~ ~s|{:floki, "~> 0.38"}|
    end

    test "companion lock is 0.38.5 and extras stay put" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"floki": {:hex, :floki, "0.38.5"|
      refute lock =~ ~s|"floki": {:hex, :floki, "0.38.4"|
      assert lock =~ ~s|"html_sanitize_ex": {:hex, :html_sanitize_ex, "1.5.6"|
      assert lock =~ ~s|"mochiweb": {:hex, :mochiweb, "3.5.0"|
    end

    test "parse, find, text, and raw_html APIs we use still exist" do
      assert function_exported?(Floki, :parse_fragment, 1)
      assert function_exported?(Floki, :parse_fragment, 2)
      assert function_exported?(Floki, :parse_fragment!, 1)
      assert function_exported?(Floki, :parse_fragment!, 2)
      assert function_exported?(Floki, :parse_document, 1)
      assert function_exported?(Floki, :find, 2)
      assert function_exported?(Floki, :text, 1)
      assert function_exported?(Floki, :raw_html, 1)
      assert function_exported?(Floki, :traverse_and_update, 2)
      assert function_exported?(Floki, :filter_out, 2)
      assert function_exported?(Floki, :attribute, 2)
    end

    test "default parser stays the built-in mochiweb backend" do
      assert Application.get_env(
               :floki,
               :html_parser,
               Floki.HTMLParser.Mochiweb
             ) ==
               Floki.HTMLParser.Mochiweb
    end
  end

  describe "0.38.5 changelog" do
    test "documents linear unbalanced-tag parsing and O(1) nth-child" do
      changelog = File.read!(@changelog)

      v0385 =
        changelog
        |> String.split("\n## ")
        |> Enum.find(&String.starts_with?(&1, "[0.38.5]"))

      assert v0385
      assert v0385 =~ "quadratic-time parsing of unbalanced tags"
      assert v0385 =~ "making parsing linear again"
      assert v0385 =~ "tree is unchanged"
      assert v0385 =~ "Optimize functional selector matching"
      assert v0385 =~ "remainder check"
      assert v0385 =~ "arithmetic"
      refute v0385 =~ "Breaking"
    end
  end

  describe "0.38.5 source" do
    test "mochiweb parser tracks open-element names to reject stray end tags" do
      source = File.read!(@mochi)

      assert source =~ "open_names_member(TagName, Names)"
      assert source =~ "open_names_new() ->"
      assert source =~ "open_names_push(Name, Names)"
      assert source =~ "is_map_key(Name, Names)"

      assert source =~
               "This is what keeps parsing of malformed input (many non-matching end"

      assert source =~ "destack(TagName, Stack, Names) when is_list(Stack) ->"
    end

    test "nth-child matching uses remainder arithmetic, not an+b streaming" do
      source = File.read!(@pseudo)

      assert source =~
               "relative_position >= b and rem(relative_position - b, a) == 0"

      assert source =~
               "relative_position <= b and rem(relative_position - b, a) == 0"

      refute source =~ "Enum.find(functional.stream"
      refute source =~ "Stream.take_while"
    end

    test "find/2 still no-ops on an unparsed HTML string" do
      finder = File.read!(@finder)

      assert finder =~
               "def find(html_as_string, _) when is_binary(html_as_string), do: []"
    end
  end

  describe "0.38.5 parse tree is unchanged for our call sites" do
    test "parse_fragment then find still locates newsletter-style nodes" do
      html = """
      <p>Hello <strong>club</strong></p>
      <figure>
        <a href="/uploads/photo.jpg">
          <img src="/uploads/photo.jpg" alt="A photo" />
        </a>
        <figcaption>Viking on a bike</figcaption>
      </figure>
      """

      assert {:ok, tree} = Floki.parse_fragment(html)
      assert [{"img", attrs, _} | _] = Floki.find(tree, "img")
      assert {"src", "/uploads/photo.jpg"} in attrs
      assert [{"figcaption", _, _} | _] = Floki.find(tree, "figcaption")

      assert Floki.find(tree, "figcaption") |> Floki.text() |> String.trim() ==
               "Viking on a bike"
    end

    test "calling find/2 on a raw HTML string still returns no matches" do
      html = ~s(<p class="intro">Hello</p>)
      assert Floki.find(html, "p") == []
      assert Floki.find(html, ".intro") == []
    end

    test "unbalanced end tags are dropped and leave nested open elements" do
      nested = fn n ->
        Enum.reduce(1..n, [], fn _, acc -> [{"div", [], acc}] end)
      end

      html = String.duplicate("<div>", 50) <> String.duplicate("</span>", 50)
      assert Floki.parse_fragment!(html) == nested.(50)
    end

    test "pathological unmatched end tags parse in linear time" do
      # Before 0.38.5 this was O(open_depth x end_tags) and grew ~4x per
      # doubling. 10_000 open <div>s plus 10_000 stray </span>s must finish
      # well under a couple of seconds on CI.
      n = 10_000
      html = String.duplicate("<div>", n) <> String.duplicate("</span>", n)

      {microseconds, parsed} = :timer.tc(fn -> Floki.parse_fragment!(html) end)

      assert match?([{"div", [], _} | _], parsed)

      assert microseconds < 5_000_000,
             "parsing #{byte_size(html)} bytes took #{div(microseconds, 1000)}ms, expected < 5000ms"
    end

    test "nth-child(an+b) still matches the same nodes" do
      html = """
      <div>
        <a href="/a">1</a>
        <a href="/b">2</a>
        <a href="/c">3</a>
        <a href="/d">4</a>
        <a href="/e">5</a>
        <a href="/f">6</a>
        <a href="/g">7</a>
      </div>
      """

      tree = Floki.parse_fragment!(html)

      assert Floki.find(tree, "a:nth-child(3n+4)") == [
               {"a", [{"href", "/d"}], ["4"]},
               {"a", [{"href", "/g"}], ["7"]}
             ]

      assert Floki.find(tree, "a:nth-child(even)") == [
               {"a", [{"href", "/b"}], ["2"]},
               {"a", [{"href", "/d"}], ["4"]},
               {"a", [{"href", "/f"}], ["6"]}
             ]

      assert Floki.find(tree, "a:nth-child(0n+1)") == [
               {"a", [{"href", "/a"}], ["1"]}
             ]
    end
  end

  describe "app still parses first, then queries the tree" do
    test "production callers still parse_fragment before find/text/raw_html" do
      newsletter = File.read!(@newsletter)
      link_tracking = File.read!(@link_tracking)
      links = File.read!(@links)
      plain_text = File.read!(@plain_text)
      sms = File.read!(@sms)

      assert newsletter =~ "Floki.parse_fragment!()"
      assert newsletter =~ ~s|Floki.find(fragment, "img")|
      assert newsletter =~ "Floki.raw_html()"

      assert link_tracking =~ "Floki.parse_fragment(html)"
      assert link_tracking =~ "Floki.traverse_and_update"
      assert link_tracking =~ "Floki.raw_html()"

      assert links =~ "Floki.parse_fragment(html)"
      assert links =~ "Floki.traverse_and_update"

      assert plain_text =~ "Floki.parse_fragment(text)"
      assert plain_text =~ "Floki.text(document)"

      assert sms =~ "Floki.parse_fragment(html)"
      assert sms =~ ~s|Floki.filter_out("figure")|
      assert sms =~ ~s|Floki.filter_out("img")|
    end

    test "newsletter email_safe_html still rewrites Trix figures" do
      html = """
      <figure>
        <a href="/uploads/photo.jpg">
          <img src="/uploads/photo.jpg" alt="A photo" />
        </a>
        <figcaption>Viking on a bike</figcaption>
      </figure>
      """

      result = NewsletterEdition.email_safe_html(html)

      assert result =~ ~s(src="/uploads/photo.jpg")
      assert result =~ ~s(alt="A photo")
      assert result =~ "Viking on a bike"
      refute result =~ "<figure"
    end

    test "SES no-track, new-tab links, entity decode, and SMS strip still work" do
      tracked =
        LinkTracking.disable_tracking(
          ~s(<p><a href="https://ysc.org/x">Go</a></p>)
        )

      assert tracked =~ "ses:no-track"
      assert tracked =~ ~s(href="https://ysc.org/x")

      blanked = Links.open_in_new_tab(~s(<a href="https://ysc.org/x">Go</a>))
      assert blanked =~ ~s(target="_blank")
      assert blanked =~ ~s(rel="noopener noreferrer")

      assert PlainText.from_html("<p>Hello&nbsp;club</p>") =~ "Hello"
      assert PlainText.from_html("<p>Hello&nbsp;club</p>") =~ "club"

      sms =
        Segment.html_to_sms_plain(
          "<p>See you</p><figure><img src='/x.jpg' alt='' /></figure>"
        )

      assert sms =~ "See you"
      refute sms =~ "<figure"
      refute sms =~ "<img"
    end
  end
end
