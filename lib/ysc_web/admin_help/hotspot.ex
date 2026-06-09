defmodule YscWeb.AdminHelp.Hotspot do
  @moduledoc false

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
      {:ok, _} -> true
      :error -> false
    end
  end

  @doc """
  Normalises guide hotspots for rendering. Viewport coordinates authored against
  the expanded sidebar layout are converted to content-relative values.
  """
  def normalize(hotspots, ghost_slug) when is_list(hotspots) do
    if admin_ghost?(ghost_slug) do
      Enum.map(hotspots, &normalize_one/1)
    else
      hotspots
    end
  end

  def normalize(hotspots, _), do: hotspots

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
  Inline CSS for a hotspot overlay. Content and sidebar areas respond to
  `--admin-help-sidebar-pct` / `--admin-help-content-pct` on the parent.
  """
  def style(%{area: :content, x: x, y: y, w: w, h: h}) do
    "left: calc(var(--admin-help-sidebar-pct) + var(--admin-help-content-pct) * #{x} / 100); " <>
      "top: #{y}%; " <>
      "width: calc(var(--admin-help-content-pct) * #{w} / 100); " <>
      "height: #{h}%;"
  end

  def style(%{area: :sidebar, x: x, y: y, w: w, h: h}) do
    "left: calc(var(--admin-help-sidebar-pct) * #{x} / 100); " <>
      "top: #{y}%; " <>
      "width: calc(var(--admin-help-sidebar-pct) * #{w} / 100); " <>
      "height: #{h}%;"
  end

  def style(%{x: x, y: y, w: w, h: h}) do
    "left: #{x}%; top: #{y}%; width: #{w}%; height: #{h}%;"
  end

  @doc "Print layout uses the expanded sidebar baseline (no live toggle)."
  def print_style(hotspot) do
    hotspot
    |> style()
    |> String.replace(
      "var(--admin-help-sidebar-pct)",
      "#{@expanded_sidebar_pct}%"
    )
    |> String.replace(
      "var(--admin-help-content-pct)",
      "#{@expanded_content_pct}%"
    )
  end

  def ghost_src(slug, sidebar_collapsed?) when is_binary(slug) do
    collapsed = if sidebar_collapsed?, do: "1", else: "0"
    "/admin/help/ghost/#{slug}?embed=1&sidebar_collapsed=#{collapsed}"
  end
end
