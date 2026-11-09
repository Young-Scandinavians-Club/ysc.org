defmodule Ysc.Html.Trix do
  @moduledoc """
  Scrubs HTML fragments through `Ysc.TrixScrubber`.

  Trix-produced bodies (posts, event details, event updates, newsletter
  notices) all go through the same allow-list. Call this instead of
  `HtmlSanitizeEx.Scrubber.scrub(html, Ysc.TrixScrubber)` at each site.

  Pair with `Ysc.Html.Links.open_in_new_tab/1` when public pages should open
  links in a new tab.

  ## Examples

      Ysc.Html.Trix.scrub("<p>Hello <strong>world</strong></p>")
      Ysc.Html.Trix.scrub(~s|<p onclick="evil()">x</p><script>alert(1)</script>|)
  """

  @doc """
  Returns `html` with disallowed tags and attributes removed.

  Accepts binaries and `nil` (treated as `""`), matching
  `HtmlSanitizeEx.Scrubber.scrub/2`. Call sites such as the admin post
  editor pass `Map.get/2` results that may be `nil` when the key is
  present with a null value.
  """
  def scrub(nil), do: ""

  def scrub(html) when is_binary(html) do
    HtmlSanitizeEx.Scrubber.scrub(html, Ysc.TrixScrubber)
  end
end
