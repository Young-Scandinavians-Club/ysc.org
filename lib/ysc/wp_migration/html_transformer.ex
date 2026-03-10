defmodule Ysc.WpMigration.HtmlTransformer do
  @moduledoc """
  Transforms WordPress post HTML into Trix-compatible HTML.

  WordPress post content can contain any combination of:
  - Block editor (Gutenberg) HTML wrapped in `<!-- wp:... -->` comment markers
  - Classic editor HTML with `wp-image-{id}` CSS classes on `<img>` tags
  - `[caption]` shortcodes wrapping an image with optional caption text
  - `[gallery ids="..."]` shortcodes for multi-image galleries

  All image `src` attributes are rewritten from the old WordPress upload URLs
  to new S3 URLs via a caller-supplied `url_map` of `attachment_id => new_url`.

  The output is compatible with Trix and safe to pass through `Ysc.TrixScrubber`
  for final sanitisation before storage in `rendered_body`.
  """

  @doc """
  Transforms WordPress HTML to Trix-compatible HTML.

  `url_map` maps WP attachment ID strings to new image URLs,
  e.g. `%{"123" => "https://cdn.example.com/migration/123/image.jpg"}`.

  Returns an empty string for `nil` or empty input.
  """
  def wp_to_trix(nil, _url_map), do: ""
  def wp_to_trix("", _url_map), do: ""

  def wp_to_trix(html, url_map) when is_binary(html) and is_map(url_map) do
    html
    |> expand_caption_shortcodes()
    |> expand_gallery_shortcodes(url_map)
    |> strip_wp_block_comments()
    |> Floki.parse_fragment!()
    |> transform_nodes(url_map)
    |> Floki.raw_html()
  end

  @doc """
  Extracts WP attachment IDs referenced in post content HTML.

  Scans for three patterns:
  - `wp-image-{id}` class on `<img>` tags (both classic and block editor)
  - `[caption id="attachment_{id}" ...]` shortcodes
  - `[gallery ids="123,456,789"]` shortcodes

  Returns a deduplicated list of attachment ID strings.
  """
  def extract_attachment_ids(nil), do: []
  def extract_attachment_ids(""), do: []

  def extract_attachment_ids(html) when is_binary(html) do
    class_ids =
      Regex.scan(~r/wp-image-(\d+)/, html, capture: :all_but_first)
      |> List.flatten()

    caption_ids =
      Regex.scan(
        ~r/\[caption[^\]]*\bid=["']?attachment_(\d+)/,
        html,
        capture: :all_but_first
      )
      |> List.flatten()

    gallery_ids =
      Regex.scan(
        ~r/\[gallery[^\]]*\bids=["']([^"'\]]+)/,
        html,
        capture: :all_but_first
      )
      |> List.flatten()
      |> Enum.flat_map(&String.split(&1, ~r/[\s,]+/))
      |> Enum.reject(&(&1 == ""))

    (class_ids ++ caption_ids ++ gallery_ids)
    |> Enum.uniq()
  end

  # ---------------------------------------------------------------------------
  # Preprocessing: shortcode expansion and block comment stripping
  # ---------------------------------------------------------------------------

  # Converts [caption id="attachment_123" align="aligncenter" width="600"]
  #   <img class="wp-image-123" src="..." alt="Alt" /> Caption text goes here
  # [/caption]
  # to:
  # <figure class="attachment attachment--preview">
  #   <img class="wp-image-123" src="..." alt="Alt">
  #   <figcaption class="attachment__caption">Caption text goes here</figcaption>
  # </figure>
  defp expand_caption_shortcodes(html) do
    Regex.replace(~r/\[caption[^\]]*\]([\s\S]*?)\[\/caption\]/, html, fn _full,
                                                                         inner ->
      inner = String.trim(inner)

      case Regex.run(~r/\A(<img[^>]*\/?>)([\s\S]*)\z/, inner) do
        [_, img_tag, rest] ->
          caption = String.trim(rest)

          figcaption =
            if caption != "",
              do:
                ~s(<figcaption class="attachment__caption">#{caption}</figcaption>),
              else: ""

          ~s(<figure class="attachment attachment--preview">#{img_tag}#{figcaption}</figure>)

        _ ->
          inner
      end
    end)
  end

  # Expands [gallery ids="123,456,789"] into a sequence of Trix figure blocks.
  # IDs not present in url_map are silently skipped.
  defp expand_gallery_shortcodes(html, url_map) do
    Regex.replace(~r/\[gallery([^\]]*)\]/, html, fn _full, attrs ->
      ids =
        case Regex.run(~r/\bids=["']([^"'\]]+)["']/, attrs) do
          [_, ids_str] ->
            ids_str
            |> String.split(~r/[\s,]+/)
            |> Enum.reject(&(&1 == ""))

          _ ->
            []
        end

      Enum.map_join(ids, "\n", fn id ->
        case Map.get(url_map, id) do
          nil ->
            ""

          url ->
            ~s(<figure class="attachment attachment--preview"><img src="#{url}"></figure>)
        end
      end)
    end)
  end

  # Strips WordPress block editor comment markers while keeping the inner HTML.
  # Examples stripped: <!-- wp:image {"id":123} --> and <!-- /wp:image -->
  defp strip_wp_block_comments(html) do
    String.replace(html, ~r/<!--\s*\/?wp:[\s\S]*?-->/, "")
  end

  # ---------------------------------------------------------------------------
  # Floki node transformation
  # ---------------------------------------------------------------------------

  defp transform_nodes(nodes, url_map) do
    Enum.flat_map(nodes, &transform_node(&1, url_map))
  end

  # Gutenberg wp-block-image figure wrapper: unwrap and process children
  # (the img inside will be wrapped in its own figure by the img handler)
  defp transform_node({"figure", attrs, children}, url_map) do
    if String.contains?(get_class(attrs), "wp-block-image") do
      transform_nodes(children, url_map)
    else
      safe_class = trix_figure_class(get_class(attrs))
      [{"figure", [{"class", safe_class}], transform_nodes(children, url_map)}]
    end
  end

  # Transform <img> into a Trix <figure><img></figure> with the new S3 src.
  # Lookup order:
  #   1. wp-image-{id} CSS class → att_id key in url_map
  #   2. Normalize the src filename (strip WP size suffix, lowercase) → filename key in url_map
  #   3. Fall back to the original src unchanged
  defp transform_node({"img", attrs, _}, url_map) do
    src = get_attr(attrs, "src")
    att_id = extract_wp_image_id(get_class(attrs))

    new_src =
      (att_id && Map.get(url_map, att_id)) ||
        lookup_by_src_filename(src, url_map) ||
        src

    if new_src && new_src != "" do
      img_attrs =
        [{"src", new_src}]
        |> maybe_add(get_attr(attrs, "alt"), "alt")
        |> maybe_add(get_attr(attrs, "width"), "width")
        |> maybe_add(get_attr(attrs, "height"), "height")

      [
        {"figure", [{"class", "attachment attachment--preview"}],
         [{"img", img_attrs, []}]}
      ]
    else
      []
    end
  end

  # figcaption: keep its class, recurse into children
  defp transform_node({"figcaption", attrs, children}, url_map) do
    safe_attrs = Enum.filter(attrs, fn {k, _} -> k == "class" end)
    [{"figcaption", safe_attrs, transform_nodes(children, url_map)}]
  end

  # Paragraph containing only figures (common in WP classic editor):
  # unwrap to avoid the invalid <p><figure>...</figure></p> nesting.
  defp transform_node({"p", _attrs, children}, url_map) do
    transformed = transform_nodes(children, url_map)
    non_ws = Enum.reject(transformed, &whitespace_text?/1)

    if non_ws != [] and Enum.all?(non_ws, &match?({"figure", _, _}, &1)) do
      non_ws
    else
      [{"p", [], transformed}]
    end
  end

  # All other elements: strip WP-specific attributes, recurse into children.
  # The TrixScrubber applied downstream provides the final allow-list.
  defp transform_node({tag, attrs, children}, url_map) do
    [{tag, strip_wp_attrs(attrs), transform_nodes(children, url_map)}]
  end

  # Text nodes and other Floki leaf values pass through unchanged.
  defp transform_node(node, _url_map), do: [node]

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp get_class(attrs), do: get_attr(attrs, "class") || ""

  defp get_attr(attrs, name) do
    case Enum.find(attrs, fn {k, _} -> k == name end) do
      {_, v} -> v
      nil -> nil
    end
  end

  defp extract_wp_image_id(class_str) do
    case Regex.run(~r/\bwp-image-(\d+)\b/, class_str) do
      [_, id] -> id
      _ -> nil
    end
  end

  # Tries to find a new URL for a WP image src by normalizing its filename and
  # looking it up in url_map (which also contains filename-keyed entries built
  # by load_media from each attachment's original_filename in meta.json).
  # Handles WP resized variants like "IMG_5613-841x1024.jpg" → "img_5613.jpg".
  defp lookup_by_src_filename(nil, _url_map), do: nil

  defp lookup_by_src_filename(src, url_map) do
    case URI.parse(src) do
      %URI{path: path} when is_binary(path) ->
        normalized =
          path
          |> Path.basename()
          |> String.replace(~r/-\d+x\d+(\.[^.]+)$/, "\\1")
          |> String.downcase()

        Map.get(url_map, normalized)

      _ ->
        nil
    end
  end

  defp maybe_add(attrs, nil, _name), do: attrs
  defp maybe_add(attrs, "", _name), do: attrs
  defp maybe_add(attrs, val, name), do: attrs ++ [{name, val}]

  defp whitespace_text?(node) when is_binary(node), do: String.trim(node) == ""
  defp whitespace_text?(_), do: false

  # Preserve trix class names; replace WP-specific classes with trix default.
  defp trix_figure_class(""), do: "attachment attachment--preview"

  defp trix_figure_class(cls) do
    if String.contains?(cls, "attachment"),
      do: cls,
      else: "attachment attachment--preview"
  end

  # Remove class, style, data-* attributes and JS event handlers from elements.
  # href, src, alt, width, height, etc. are kept for the TrixScrubber to filter.
  defp strip_wp_attrs(attrs) do
    Enum.reject(attrs, fn {k, _} ->
      k == "class" or
        k == "style" or
        String.starts_with?(k, "data-") or
        String.starts_with?(k, "on")
    end)
  end
end
