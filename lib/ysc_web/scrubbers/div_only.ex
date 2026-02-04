defmodule YscWeb.Scrubber.StripEverythingExceptText do
  @moduledoc """
  Strips all tags execpt `div`
  """

  require HtmlSanitizeEx.Scrubber.Meta
  alias HtmlSanitizeEx.Scrubber.Meta

  # Removes any CDATA tags before the traverser/scrubber runs.
  Meta.remove_cdata_sections_before_scrub()

  Meta.strip_comments()
  Meta.allow_tag_with_these_attributes("div", [])
  Meta.allow_tag_with_these_attributes("br", [])
  Meta.allow_tag_with_these_attributes("strong", [])
  Meta.allow_tag_with_these_attributes("em", [])

  Meta.strip_everything_not_covered()
end
