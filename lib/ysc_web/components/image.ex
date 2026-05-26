defmodule YscWeb.Components.Image do
  @moduledoc """
  LiveView component for displaying images with blur hash placeholders.

  Renders images with progressive loading using blur hash placeholders.
  """
  use YscWeb, :live_component

  alias Ysc.Media.Image
  alias Ysc.Media

  def render(assigns) do
    ~H"""
    <div class={"relative w-full #{@aspect_class}"}>
      <canvas
        id={"blur-hash-image-#{@id}"}
        src={get_blur_hash(@image)}
        class="absolute inset-0 z-0 rounded-lg w-full h-full object-cover"
        phx-hook="BlurHashCanvas"
      >
      </canvas>

      <img
        src={image_url(@image, @preferred_type)}
        srcset={image_srcset(@image)}
        sizes={@sizes}
        id={"image-#{@id}"}
        loading={@loading}
        decoding={@decoding}
        fetchpriority={@fetchpriority}
        width={image_dimension(@image, :width)}
        height={image_dimension(@image, :height)}
        phx-hook="BlurHashImage"
        class="absolute inset-0 z-[1] opacity-0 transition-opacity duration-300 ease-out rounded-lg w-full h-full object-cover"
        alt={
          if @image, do: @image.alt_text || @image.title || "Image", else: "Image"
        }
      />
    </div>
    """
  end

  def update(assigns, socket) do
    socket = socket |> assign(assigns)

    aspect_class = Map.get(assigns, :aspect_class, "aspect-video")
    preferred_type = Map.get(assigns, :preferred_type, nil)
    loading = Map.get(assigns, :loading, "lazy")
    decoding = Map.get(assigns, :decoding, "async")
    fetchpriority = Map.get(assigns, :fetchpriority, nil)
    sizes = Map.get(assigns, :sizes, "(max-width: 1024px) 100vw, 50vw")

    socket =
      socket
      |> assign(:aspect_class, aspect_class)
      |> assign(:preferred_type, preferred_type)
      |> assign(:loading, loading)
      |> assign(:decoding, decoding)
      |> assign(:fetchpriority, fetchpriority)
      |> assign(:sizes, sizes)

    # Use preloaded image if available (from batch loading), otherwise fetch
    image =
      case Map.get(assigns, :image) do
        nil ->
          if assigns.image_id == nil || assigns.image_id == "" do
            nil
          else
            Media.get_image!(assigns.image_id)
          end

        preloaded_image ->
          preloaded_image
      end

    {:ok, socket |> assign(image: image)}
  end

  defp get_blur_hash(nil), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: nil}), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: blur_hash}), do: blur_hash

  # Helper function to get the best available image path with fallbacks
  # Supports preferred_type: :optimized, :thumbnail, :raw, or nil (default)
  defp image_url(nil, _preferred_type), do: "/images/ysc_logo.webp"

  # Prefer optimized image (for detail pages) - skip thumbnail, fallback to raw
  defp image_url(%Image{} = image, :optimized) do
    cond do
      not is_nil(image.optimized_image_path) -> image.optimized_image_path
      not is_nil(image.raw_image_path) -> image.raw_image_path
      true -> "/images/ysc_logo.webp"
    end
  end

  # Prefer thumbnail (for lists/grids) - fallback to optimized, then raw
  defp image_url(%Image{} = image, :thumbnail) do
    cond do
      not is_nil(image.thumbnail_path) -> image.thumbnail_path
      not is_nil(image.optimized_image_path) -> image.optimized_image_path
      not is_nil(image.raw_image_path) -> image.raw_image_path
      true -> "/images/ysc_logo.webp"
    end
  end

  # Prefer raw image only
  defp image_url(%Image{} = image, :raw) do
    image.raw_image_path || "/images/ysc_logo.webp"
  end

  # Default: thumbnail > optimized > raw (backward compatible)
  defp image_url(%Image{} = image, nil) do
    cond do
      not is_nil(image.thumbnail_path) -> image.thumbnail_path
      not is_nil(image.optimized_image_path) -> image.optimized_image_path
      not is_nil(image.raw_image_path) -> image.raw_image_path
      true -> "/images/ysc_logo.webp"
    end
  end

  # Build a srcset string from thumbnail (500w) and optimized (1920w) when both exist,
  # so the browser picks the right size for the current viewport.
  defp image_srcset(nil), do: nil

  defp image_srcset(%Image{thumbnail_path: nil}), do: nil
  defp image_srcset(%Image{optimized_image_path: nil}), do: nil

  defp image_srcset(%Image{
         thumbnail_path: thumb,
         optimized_image_path: optimized
       }) do
    "#{thumb} 500w, #{optimized} 1920w"
  end

  defp image_dimension(nil, _), do: nil
  defp image_dimension(%Image{} = image, :width), do: image.width
  defp image_dimension(%Image{} = image, :height), do: image.height
end
