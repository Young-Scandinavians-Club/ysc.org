defmodule YscWeb.AdminHelp.Hotspot do
  @moduledoc """
  Hotspot positioning for admin help screenshots and ghost previews.

  Each hotspot has a `label` plus coordinates for the **expanded** and
  **collapsed** sidebar layouts. Toggle the admin sidebar in a guide to verify
  both; CSS switches between the two sets automatically.

  ## Authoring

  Preferred form (tune each layout separately):

      hotspots: [
        %{
          label: "Publish",
          expanded: %{x: 70, y: 4, w: 12, h: 6},
          collapsed: %{x: 74, y: 4, w: 14, h: 6}
        }
      ]

  Shorthand — one box used for both until you add `collapsed:`:

      hotspots: [%{x: 70, y: 4, w: 12, h: 6, label: "Publish"}]

  Coordinates are percentages of the 1280×800 ghost viewport. For admin ghosts
  (not `public-*`), omit `area` to author against the **expanded** sidebar;
  values are converted to content-relative positioning. You can also set
  `area: :content`, `:sidebar`, or `:viewport` explicitly per layout.

  `collapsed:` is optional; when omitted it copies `expanded:`.

  ## Styles

  - `:highlight` (default) — filled overlay box; best for compact UI controls.
  - `:hint` — dashed frame and a small corner beacon; content stays visible.
    Use on large public previews (e.g. agenda timeline).
  """

  alias YscWeb.AdminHelp.Ghost.Registry

  @viewport_w 1280
  @sidebar_expanded_px 288
  @content_expanded_px 992

  @expanded_sidebar_pct 22.5
  @collapsed_sidebar_pct 5.0
  @expanded_content_pct 77.5
  @collapsed_content_pct 95.0

  def expanded_sidebar_pct, do: @expanded_sidebar_pct
  def collapsed_sidebar_pct, do: @collapsed_sidebar_pct
  def expanded_content_pct, do: @expanded_content_pct
  def collapsed_content_pct, do: @collapsed_content_pct

  @doc """
  Admin ghost previews (not `public-*`) use coordinates relative to the main
  content column so hotspots track when the sidebar is expanded or collapsed.
  """
  def admin_ghost?(nil), do: false

  def admin_ghost?(slug) when is_binary(slug) do
    not String.starts_with?(slug, "public-") and uses_admin_sidebar?(slug)
  end

  defp uses_admin_sidebar?(slug) do
    case Registry.fetch(slug) do
      {:ok, %{public?: true}} -> false
      {:ok, %{sidebar?: false}} -> false
      {:ok, _} -> true
      :error -> false
    end
  end

  @doc """
  Normalises guide hotspots for rendering.

  Returns `%{label:, expanded:, collapsed:}` per hotspot. Viewport coordinates
  authored against the expanded sidebar layout are converted to content-relative
  values for admin ghosts.
  """
  def normalize(hotspots, ghost_slug) when is_list(hotspots) do
    Enum.map(hotspots, &normalize_hotspot(&1, ghost_slug))
  end

  def normalize(hotspots, _), do: hotspots

  defp normalize_hotspot(hotspot, ghost_slug) do
    {label, expanded_raw, collapsed_raw} = split_layouts(hotspot)

    %{
      label: label,
      style: normalize_style(hotspot),
      expanded: normalize_coords(expanded_raw, ghost_slug),
      collapsed: normalize_coords(collapsed_raw, ghost_slug)
    }
  end

  defp normalize_style(%{style: :hint}), do: :hint
  defp normalize_style(_), do: :highlight

  @doc "CSS class for a hotspot's visual style (`:highlight` or `:hint`)."
  def style_class(%{style: :hint}), do: "admin-help-hotspot--hint"
  def style_class(_), do: nil

  def print_marker_class(%{style: :hint}), do: "admin-help-print-marker--hint"
  def print_marker_class(_), do: nil

  def hint?(%{style: :hint}), do: true
  def hint?(_), do: false

  defp split_layouts(%{label: label, expanded: expanded} = hotspot) do
    collapsed = Map.get(hotspot, :collapsed, expanded)
    {label, expanded, collapsed}
  end

  defp split_layouts(%{label: label} = hotspot) do
    coords = Map.take(hotspot, [:area, :x, :y, :w, :h])
    {label, coords, coords}
  end

  defp normalize_coords(coords, ghost_slug) do
    if admin_ghost?(ghost_slug) do
      normalize_one(coords)
    else
      Map.put_new(coords, :area, :viewport)
    end
  end

  defp normalize_one(%{area: area} = hotspot)
       when area in [:content, :sidebar, :viewport],
       do: hotspot

  defp normalize_one(hotspot) do
    hotspot
    |> viewport_expanded_to_content()
  end

  defp viewport_expanded_to_content(%{x: x, w: w} = hotspot) do
    left_px = x / 100 * @viewport_w
    width_px = w / 100 * @viewport_w

    hotspot
    |> Map.put(:area, :content)
    |> Map.put(
      :x,
      (left_px - @sidebar_expanded_px) / @content_expanded_px * 100
    )
    |> Map.put(:w, width_px / @content_expanded_px * 100)
  end

  @doc """
  CSS custom properties for hotspot positioning (rules live in app.css).

  Sets `-expanded` and `-collapsed` variables; the active set is chosen by
  `html.sidebar-collapsed` on `.admin-help-sidebar-aware` containers.
  """
  def css_vars(%{expanded: expanded, collapsed: collapsed}) do
    [
      layout_css_vars(expanded, "expanded"),
      layout_css_vars(collapsed, "collapsed")
    ]
    |> Enum.join(" ")
  end

  @doc "Print layout uses the expanded sidebar baseline (no live toggle)."
  def print_css_vars(%{expanded: expanded}) do
    expanded
    |> layout_css_vars("expanded")
    |> String.replace(
      "var(--admin-help-sidebar-pct)",
      "#{@expanded_sidebar_pct}%"
    )
    |> String.replace(
      "var(--admin-help-content-pct)",
      "#{@expanded_content_pct}%"
    )
  end

  defp layout_css_vars(%{area: :content, x: x, y: y, w: w, h: h}, suffix) do
    p = "--admin-help-hotspot"

    "#{p}-left-#{suffix}: calc(var(--admin-help-sidebar-pct) + var(--admin-help-content-pct) * #{x} / 100); " <>
      "#{p}-top-#{suffix}: #{y}%; " <>
      "#{p}-width-#{suffix}: calc(var(--admin-help-content-pct) * #{w} / 100); " <>
      "#{p}-height-#{suffix}: #{h}%;"
  end

  defp layout_css_vars(%{area: :sidebar, x: x, y: y, w: w, h: h}, suffix) do
    p = "--admin-help-hotspot"

    "#{p}-left-#{suffix}: calc(var(--admin-help-sidebar-pct) * #{x} / 100); " <>
      "#{p}-top-#{suffix}: #{y}%; " <>
      "#{p}-width-#{suffix}: calc(var(--admin-help-sidebar-pct) * #{w} / 100); " <>
      "#{p}-height-#{suffix}: #{h}%;"
  end

  defp layout_css_vars(%{x: x, y: y, w: w, h: h}, suffix) do
    p = "--admin-help-hotspot"

    "#{p}-left-#{suffix}: #{x}%; " <>
      "#{p}-top-#{suffix}: #{y}%; " <>
      "#{p}-width-#{suffix}: #{w}%; " <>
      "#{p}-height-#{suffix}: #{h}%;"
  end

  @doc """
  Ghost iframe URL. Pass `scroll_to` with a section element id to frame that
  part of a long preview (e.g. `ghost-event-agenda-section`).
  """
  def ghost_src(slug, sidebar_collapsed?, scroll_to \\ nil)
      when is_binary(slug) do
    collapsed = if sidebar_collapsed?, do: "1", else: "0"

    query =
      "embed=1&sidebar_collapsed=#{collapsed}" <>
        scroll_to_query(scroll_to)

    "/admin/help/ghost/#{slug}?#{query}"
  end

  def valid_scroll_target?(target) when is_binary(target) do
    target != "" and Regex.match?(~r/^[a-zA-Z][a-zA-Z0-9_-]*$/, target)
  end

  def valid_scroll_target?(_), do: false

  defp scroll_to_query(nil), do: ""
  defp scroll_to_query(""), do: ""

  defp scroll_to_query(target) do
    if valid_scroll_target?(target) do
      "&scroll_to=" <> URI.encode_www_form(target)
    else
      ""
    end
  end
end
