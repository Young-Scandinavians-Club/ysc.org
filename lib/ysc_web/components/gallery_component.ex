defmodule YscWeb.Components.GalleryComponent do
  @moduledoc """
  LiveView component for displaying image galleries.

  Provides an interactive gallery view for displaying multiple images.
  """
  use YscWeb, :live_component

  alias Ysc.Media.Image

  @spec render(any()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div>
      <div
        id={@id}
        phx-update="stream"
        class="gap-3 md:gap-4 grid grid-cols-2 md:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5 3xl:grid-cols-7 4xl:grid-cols-9"
      >
        <%= for {id, image} <- @images do %>
          <button
            phx-click={JS.navigate(~p"/admin/media/upload/#{image.id}")}
            id={id}
            class="mb-4 group relative w-full rounded-lg aspect-square border border-zinc-200 cursor-pointer hover:border-zinc-400 hover:shadow-md transition-all duration-200 overflow-hidden"
          >
            <canvas
              id={"blur-hash-image-#{image.id}"}
              src={get_blur_hash(image)}
              class="absolute inset-0 z-0 rounded-lg w-full h-full object-cover"
              phx-hook="BlurHashCanvas"
            >
            </canvas>

            <img
              class="absolute inset-0 z-[1] opacity-0 transition-opacity duration-300 ease-out rounded-lg w-full h-full object-cover group-hover:opacity-100"
              id={"image-#{image.id}"}
              src={get_image_path(image)}
              loading="lazy"
              phx-hook="BlurHashImage"
              alt={image.alt_text || image.title || "Image"}
            />

            <div
              :if={image.title != nil or image.alt_text != nil}
              class="absolute z-[2] hidden group-hover:block inset-x-0 bottom-0 px-2 py-2 bg-gradient-to-t from-zinc-900/90 via-zinc-900/80 to-transparent"
            >
              <p
                :if={image.title != nil}
                class="text-xs font-medium text-white truncate"
                title={image.title}
              >
                <%= image.title %>
              </p>
              <p
                :if={image.title == nil and image.alt_text != nil}
                class="text-xs font-medium text-white/90 truncate"
                title={image.alt_text}
              >
                <%= image.alt_text %>
              </p>
            </div>
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  defp get_blur_hash(%Image{blur_hash: nil}), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: blur_hash}), do: blur_hash

  defp get_image_path(%Image{thumbnail_path: nil} = image),
    do: image.raw_image_path

  defp get_image_path(%Image{optimized_image_path: nil} = image),
    do: image.raw_image_path

  defp get_image_path(%Image{thumbnail_path: thumbnail_path}),
    do: thumbnail_path

  defp get_image_path(%Image{optimized_image_path: optimized_path}),
    do: optimized_path
end
