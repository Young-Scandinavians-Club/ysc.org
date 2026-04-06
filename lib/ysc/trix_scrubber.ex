defmodule Ysc.TrixScrubber do
  @moduledoc """
  HTML scrubber for content produced by the Trix editor.

  Extends BasicHTML to also permit the structural tags that Trix uses when
  embedding images (`figure`, `figcaption`, `a` inside figures) while still
  stripping dangerous attributes such as `style`, `data-trix-*`, and JS event
  handlers.
  """

  require HtmlSanitizeEx.Scrubber.Meta
  alias HtmlSanitizeEx.Scrubber.Meta

  @valid_schemes ["http", "https", "mailto"]

  Meta.remove_cdata_sections_before_scrub()
  Meta.strip_comments()

  # Links
  Meta.allow_tag_with_uri_attributes("a", ["href"], @valid_schemes)
  Meta.allow_tag_with_these_attributes("a", ["name", "title", "tabindex"])

  # Basic text formatting
  Meta.allow_tag_with_these_attributes("b", [])
  Meta.allow_tag_with_these_attributes("blockquote", [])
  Meta.allow_tag_with_these_attributes("br", [])
  Meta.allow_tag_with_these_attributes("code", [])
  Meta.allow_tag_with_these_attributes("del", [])
  Meta.allow_tag_with_these_attributes("div", [])
  Meta.allow_tag_with_these_attributes("em", [])
  Meta.allow_tag_with_these_attributes("h1", [])
  Meta.allow_tag_with_these_attributes("h2", [])
  Meta.allow_tag_with_these_attributes("h3", [])
  Meta.allow_tag_with_these_attributes("h4", [])
  Meta.allow_tag_with_these_attributes("h5", [])
  Meta.allow_tag_with_these_attributes("h6", [])
  Meta.allow_tag_with_these_attributes("hr", [])
  Meta.allow_tag_with_these_attributes("i", [])
  Meta.allow_tag_with_these_attributes("li", [])
  Meta.allow_tag_with_these_attributes("ol", [])
  Meta.allow_tag_with_these_attributes("p", [])
  Meta.allow_tag_with_these_attributes("pre", [])
  Meta.allow_tag_with_these_attributes("span", [])
  Meta.allow_tag_with_these_attributes("strong", [])
  Meta.allow_tag_with_these_attributes("u", [])
  Meta.allow_tag_with_these_attributes("ul", [])

  # Tables
  Meta.allow_tag_with_these_attributes("table", [])
  Meta.allow_tag_with_these_attributes("tbody", [])
  Meta.allow_tag_with_these_attributes("td", [])
  Meta.allow_tag_with_these_attributes("th", [])
  Meta.allow_tag_with_these_attributes("thead", [])
  Meta.allow_tag_with_these_attributes("tr", [])

  # Trix image attachments
  Meta.allow_tag_with_uri_attributes("img", ["src"], @valid_schemes)

  Meta.allow_tag_with_these_attributes("img", [
    "width",
    "height",
    "alt",
    "title"
  ])

  Meta.allow_tag_with_these_attributes("figure", [
    "class",
    "data-trix-attachment",
    "data-trix-content-type",
    "data-trix-attributes"
  ])

  Meta.allow_tag_with_these_attributes("figcaption", ["class"])

  @before_compile HtmlSanitizeEx.ScrubberCompiler
end
