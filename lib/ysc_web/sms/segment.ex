defmodule YscWeb.Sms.Segment do
  @moduledoc """
  Builds and analyzes SMS bodies for length / segment counting.

  Segment math follows carrier rules:

  - **GSM-7** when every character is in the GSM 03.38 default alphabet
    (or its extension table). Single segment = 160 septets; concatenated =
    153 septets each (UDH overhead).
  - **UCS-2** when any non-GSM character is present (emoji, smart quotes,
    em dashes, non-GSM accents, …). Single = 70 UTF-16 code units;
    concatenated = 67 each.
  - GSM-7 **extended** characters (`^ | € { } [ ] ~ \\`) cost **2 septets**
    each (escape + character).
  - Line breaks are normalized to a single LF (`\\n`), which costs **1**
    GSM-7 septet / UCS-2 unit. CRLF is never left in outbound bodies.

  Soft-caps messages at 2 SMS segments so admin text blasts cannot become
  multi-part storms from long HTML email bodies.
  """

  alias YscWeb.PlainText

  @max_segments 2
  @gsm7_single 160
  @gsm7_concat 153
  @ucs2_single 70
  @ucs2_concat 67

  # GSM 03.38 default alphabet (basic). Explicit codepoints avoid source
  # encoding / heredoc pitfalls. Includes both Ç and ç (handset variance).
  @gsm7_basic MapSet.new([
                # 0x00-0x0F
                ?@,
                ?£,
                ?$,
                ?¥,
                ?è,
                ?é,
                ?ù,
                ?ì,
                ?ò,
                ?Ç,
                ?ç,
                ?\n,
                ?Ø,
                ?ø,
                ?\r,
                ?Å,
                ?å,
                # 0x10-0x1F (0x1B is ESC — not a content character)
                ?Δ,
                ?_,
                ?Φ,
                ?Γ,
                ?Λ,
                ?Ω,
                ?Π,
                ?Ψ,
                ?Σ,
                ?Θ,
                ?Ξ,
                ?Æ,
                ?æ,
                ?ß,
                ?É,
                # 0x20-0x3F
                ?\s,
                ?!,
                ?",
                ?#,
                ?¤,
                ?%,
                ?&,
                ?',
                ?(,
                ?),
                ?*,
                ?+,
                ?,,
                ?-,
                ?.,
                ?/,
                ?0,
                ?1,
                ?2,
                ?3,
                ?4,
                ?5,
                ?6,
                ?7,
                ?8,
                ?9,
                ?:,
                ?;,
                ?<,
                ?=,
                ?>,
                ??,
                # 0x40-0x5F
                ?¡,
                ?A,
                ?B,
                ?C,
                ?D,
                ?E,
                ?F,
                ?G,
                ?H,
                ?I,
                ?J,
                ?K,
                ?L,
                ?M,
                ?N,
                ?O,
                ?P,
                ?Q,
                ?R,
                ?S,
                ?T,
                ?U,
                ?V,
                ?W,
                ?X,
                ?Y,
                ?Z,
                ?Ä,
                ?Ö,
                ?Ñ,
                ?Ü,
                ?§,
                # 0x60-0x7F
                ?¿,
                ?a,
                ?b,
                ?c,
                ?d,
                ?e,
                ?f,
                ?g,
                ?h,
                ?i,
                ?j,
                ?k,
                ?l,
                ?m,
                ?n,
                ?o,
                ?p,
                ?q,
                ?r,
                ?s,
                ?t,
                ?u,
                ?v,
                ?w,
                ?x,
                ?y,
                ?z,
                ?ä,
                ?ö,
                ?ñ,
                ?ü,
                ?à
              ])

  # GSM 03.38 extension table — each costs 2 septets (ESC + character)
  @gsm7_extended MapSet.new([?^, ?{, ?}, ?\\, ?[, ?~, ?], ?|, ?€])

  @type encoding :: :gsm7 | :ucs2

  @type analysis :: %{
          body: String.t(),
          char_count: non_neg_integer(),
          segment_count: pos_integer(),
          encoding: encoding(),
          single_limit: pos_integer(),
          truncated?: boolean(),
          multi_segment?: boolean()
        }

  @doc """
  Strips HTML (preserving line breaks), builds a `[YSC]`-prefixed SMS body,
  soft-caps at 2 segments, and returns length / segment analysis for UI + delivery.

  `char_count` is the septet count (GSM-7) or UTF-16 code-unit count (UCS-2)
  used for segment limits — not necessarily `String.length/1`.
  """
  @spec build_event_update_sms(String.t(), String.t() | nil, String.t()) ::
          analysis()
  def build_event_update_sms(event_title, update_title, html_body)
      when is_binary(event_title) and is_binary(html_body) do
    plain = html_to_sms_plain(html_body)

    headline =
      case update_title do
        title when is_binary(title) ->
          trimmed = String.trim(title)
          if trimmed != "", do: trimmed, else: String.trim(event_title)

        _ ->
          String.trim(event_title)
      end

    headline = if headline == "", do: "Event update", else: headline

    plain =
      if plain == "" do
        "See email for details."
      else
        plain
      end

    # Avoid Template.format/1 — it collapses newlines into spaces.
    # Note: `[` and `]` in `[YSC]` are GSM-7 extended (2 septets each).
    body =
      "[YSC] #{headline}: #{plain}"
      |> normalize_sms_whitespace()

    analyze_and_cap(body)
  end

  @doc false
  def html_to_sms_plain(html) when is_binary(html) do
    html
    |> strip_media_for_sms()
    |> PlainText.from_html()
    |> normalize_sms_whitespace()
  end

  # Trix stores images (and captions) in <figure>…</figure>; drop those and
  # any leftover <img> tags so SMS only carries the prose.
  defp strip_media_for_sms(html) when is_binary(html) do
    case Floki.parse_fragment(html) do
      {:ok, nodes} ->
        nodes
        |> Floki.filter_out("figure")
        |> Floki.filter_out("img")
        |> Floki.raw_html()

      {:error, _} ->
        html
        |> String.replace(~r/<figure\b[^>]*>.*?<\/figure>/is, "")
        |> String.replace(~r/<img\b[^>]*\/?>/i, "")
    end
  end

  @doc """
  Analyzes an SMS body and soft-caps it at #{@max_segments} segments.
  """
  @spec analyze_and_cap(String.t()) :: analysis()
  def analyze_and_cap(body) when is_binary(body) do
    body = normalize_sms_whitespace(body)
    encoding = encoding(body)
    units = unit_count(body, encoding)
    max_units = max_units_for_segments(@max_segments, encoding)

    {final_body, truncated?} =
      if units > max_units do
        {truncate_to_units(body, max_units, encoding), true}
      else
        {body, false}
      end

    # Truncation can drop the only UCS-2 characters and flip encoding.
    final_encoding = encoding(final_body)
    final_units = unit_count(final_body, final_encoding)
    segment_count = segment_count(final_units, final_encoding)

    {single_limit, _concat} = limits(final_encoding)

    %{
      body: final_body,
      char_count: final_units,
      segment_count: segment_count,
      encoding: final_encoding,
      single_limit: single_limit,
      truncated?: truncated?,
      multi_segment?: segment_count >= 2
    }
  end

  @doc false
  def encoding(body) when is_binary(body) do
    if gsm7?(body), do: :gsm7, else: :ucs2
  end

  @doc """
  Counts GSM-7 septets or UCS-2/UTF-16 code units for segment math.
  """
  @spec unit_count(String.t(), encoding()) :: non_neg_integer()
  def unit_count(body, :gsm7) do
    body
    |> String.to_charlist()
    |> Enum.reduce(0, fn char, acc ->
      cond do
        MapSet.member?(@gsm7_extended, char) -> acc + 2
        MapSet.member?(@gsm7_basic, char) -> acc + 1
        # Should not happen when encoding/1 returned :gsm7
        true -> acc + 1
      end
    end)
  end

  def unit_count(body, :ucs2) do
    # UCS-2 SMS length is in UTF-16 code units (BMP = 1, supplementary = 2)
    body
    |> String.to_charlist()
    |> Enum.reduce(0, fn
      codepoint, acc when codepoint > 0xFFFF -> acc + 2
      _codepoint, acc -> acc + 1
    end)
  end

  @doc false
  def segment_count(units, encoding) when units >= 0 do
    {single, concat} = limits(encoding)

    cond do
      units == 0 -> 1
      units <= single -> 1
      true -> div(units + concat - 1, concat)
    end
  end

  @doc false
  def max_units_for_segments(segments, encoding) when segments >= 1 do
    {single, concat} = limits(encoding)

    if segments == 1 do
      single
    else
      segments * concat
    end
  end

  defp limits(:gsm7), do: {@gsm7_single, @gsm7_concat}
  defp limits(:ucs2), do: {@ucs2_single, @ucs2_concat}

  defp gsm7?(body) do
    body
    |> String.to_charlist()
    |> Enum.all?(fn char ->
      MapSet.member?(@gsm7_basic, char) or MapSet.member?(@gsm7_extended, char)
    end)
  end

  # Collapse horizontal whitespace; normalize all line endings to LF (`\n`)
  # so each break costs 1 unit (not CRLF = 2).
  defp normalize_sms_whitespace(text) when is_binary(text) do
    text
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> String.replace(~r/[^\S\n]+/u, " ")
    |> String.replace(~r/ *\n */u, "\n")
    |> String.replace(~r/\n{3,}/u, "\n\n")
    |> String.trim()
  end

  defp truncate_to_units(body, max_units, encoding) when max_units > 3 do
    # Reserve 3 units for ASCII ellipsis "..." (always GSM-basic / BMP)
    target = max_units - 3
    do_truncate(body, target, encoding) <> "..."
  end

  defp truncate_to_units(body, max_units, encoding) do
    do_truncate(body, max_units, encoding)
  end

  defp do_truncate(body, max_units, encoding) do
    body
    |> String.graphemes()
    |> Enum.reduce_while({"", 0}, fn grapheme, {acc, _used} ->
      next = acc <> grapheme
      next_units = unit_count(next, encoding)

      if next_units <= max_units do
        {:cont, {next, next_units}}
      else
        {:halt, {acc, 0}}
      end
    end)
    |> elem(0)
  end
end
