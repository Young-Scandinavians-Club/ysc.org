defmodule YscWeb.Components.ImageCarouselAutoplay do
  @moduledoc """
  Hero-style image carousel with client-side autoplay via `ImageCarouselAutoplay` hook.

  Wraps `YscWeb.Components.ImageCarousel.image_carousel/1` for full-bleed booking
  page heroes (hook wrapper, optional dark scrim).

  ## Examples

      <.image_carousel_autoplay
        wrapper_id="clear-lake-carousel-wrapper"
        id="about-the-clear-lake-cabin-carousel"
        images={clear_lake_hero_images()}
      />
  """
  use Phoenix.Component

  import YscWeb.Components.ImageCarousel, only: [image_carousel: 1]

  attr :wrapper_id, :string,
    required: true,
    doc: "DOM id for the autoplay hook wrapper"

  attr :id, :string,
    required: true,
    doc: "Unique ID passed to the inner carousel"

  attr :images, :list,
    required: true,
    doc: "List of image maps with :src and :alt keys"

  attr :wrapper_class, :string,
    default: "absolute inset-0 h-full w-full z-[2]",
    doc: "Classes on the hook wrapper element"

  attr :scrim, :boolean,
    default: true,
    doc: "When true, renders a dark overlay above slides (hero sections)"

  def image_carousel_autoplay(assigns) do
    ~H"""
    <div id={@wrapper_id} phx-hook="ImageCarouselAutoplay" class={@wrapper_class}>
      <.image_carousel id={@id} images={@images} class="h-full w-full" />
      <div
        :if={@scrim}
        class="absolute inset-0 z-[5] bg-black/40 pointer-events-none"
        aria-hidden="true"
      >
      </div>
    </div>
    """
  end
end
