defmodule YscWeb.Components.ImageCarousel do
  @moduledoc """
  A modern CSS-only image carousel component.

  Uses pure CSS animations and radio button navigation for a lightweight,
  JavaScript-free carousel experience.

  ## Examples

      <.image_carousel
        id="tahoe-cabin-carousel"
        images={[
          %{src: ~p"/images/tahoe-exterior.jpg", alt: "Tahoe cabin exterior"},
          %{src: ~p"/images/tahoe-living-room.jpg", alt: "Tahoe cabin living room"},
          %{src: ~p"/images/tahoe-kitchen.jpg", alt: "Tahoe cabin kitchen"},
          %{src: ~p"/images/tahoe-bedroom.jpg", alt: "Tahoe cabin bedroom"}
        ]}
        class="my-8"
      />

  ## Features

  - Pure CSS implementation (no JavaScript required)
  - Smooth transitions with cubic-bezier easing
  - Navigation arrows (appear on hover)
  - Dot indicators for direct slide navigation
  - Fully responsive design
  - Accessible with proper ARIA labels

  """
  use Phoenix.Component

  attr :id, :string, required: true, doc: "Unique ID for the carousel"

  attr :images, :list,
    required: true,
    doc: "List of image maps with :src and :alt keys"

  attr :class, :string,
    default: "",
    doc: "Additional CSS classes for the container"

  slot :overlay,
    doc:
      "Optional overlay content (e.g., title section) that appears over the carousel"

  def image_carousel(assigns) do
    assigns =
      assigns
      |> assign(:image_count, length(assigns.images))
      |> assign(:has_overlay, assigns.overlay != [])
      |> assign(:has_height_class, String.contains?(assigns.class || "", "h-"))

    ~H"""
    <div class={["image-carousel-container", @class]}>
      <style>
        /* Hide radio buttons */
        .image-carousel-container input[type="radio"] {
          display: none;
        }

        /* Carousel wrapper */
        .image-carousel-container .carousel-wrapper {
          position: relative;
          width: 100%;
          overflow: hidden;
          background: #f3f4f6;
        }

        /* Only apply aspect-ratio and border-radius if no height class is provided */
        <%= if not @has_height_class do %>
        .image-carousel-container .carousel-wrapper {
          aspect-ratio: 16 / 9;
          border-radius: 0.5rem;
        }
        <% end %>

        /* When height class is provided, use height: 100% to fill parent and remove border-radius */
        <%= if @has_height_class do %>
        .image-carousel-container.h-full .carousel-wrapper,
        .image-carousel-container[class*="h-"] .carousel-wrapper {
          height: 100%;
          border-radius: 0;
        }
        <% end %>

        /* Slides container */
        .image-carousel-container .carousel-slides {
          display: flex;
          width: calc(100% * <%= @image_count %>);
          height: 100%;
          transition: transform 0.6s cubic-bezier(0.4, 0, 0.2, 1);
        }

        /* Individual slide */
        .image-carousel-container .carousel-slide {
          width: calc(100% / <%= @image_count %>);
          height: 100%;
          flex-shrink: 0;
        }

        .image-carousel-container .carousel-slide img {
          width: 100%;
          height: 100%;
          object-fit: cover;
          display: block;
        }

        /* Navigation buttons */
        .image-carousel-container .carousel-nav {
          position: absolute;
          top: 50%;
          transform: translateY(-50%);
          background: rgba(255, 255, 255, 0.9);
          border: none;
          width: 3rem;
          height: 3rem;
          border-radius: 50%;
          cursor: pointer;
          display: none;
          align-items: center;
          justify-content: center;
          z-index: 10;
          transition: all 0.2s ease;
          box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
          opacity: 0;
          pointer-events: none;
        }

        .image-carousel-container .carousel-nav:hover {
          background: rgba(255, 255, 255, 1);
          box-shadow: 0 4px 12px rgba(0, 0, 0, 0.2);
          transform: translateY(-50%) scale(1.05);
        }

        .image-carousel-container .carousel-nav:active {
          transform: translateY(-50%) scale(0.95);
        }

        .image-carousel-container .carousel-nav.prev {
          left: 1rem;
        }

        .image-carousel-container .carousel-nav.next {
          right: 1rem;
        }

        .image-carousel-container .carousel-nav svg {
          width: 1.5rem;
          height: 1.5rem;
          color: #374151;
        }

        /* Show navigation buttons on hover */
        .image-carousel-container .carousel-wrapper:hover .carousel-nav {
          opacity: 1;
          pointer-events: all;
        }

        /* Overlay layer - appears when overlay slot is provided */
        .image-carousel-container .carousel-overlay {
          position: absolute;
          inset: 0;
          background: linear-gradient(to top, rgba(0, 0, 0, 0.7), rgba(0, 0, 0, 0.3), rgba(0, 0, 0, 0.1));
          z-index: 5;
          pointer-events: none;
        }

        /* Overlay content */
        .image-carousel-container .carousel-overlay-content {
          position: absolute;
          inset: 0;
          z-index: 6;
          pointer-events: none;
        }

        /* Dots navigation */
        .image-carousel-container .carousel-dots {
          position: absolute;
          bottom: 1rem;
          left: 50%;
          transform: translateX(-50%);
          display: flex;
          gap: 0.5rem;
          z-index: 10;
        }

        .image-carousel-container .carousel-dot {
          width: 0.75rem;
          height: 0.75rem;
          border-radius: 50%;
          background: rgba(255, 255, 255, 0.33);
          border: 1px solid rgba(222, 222, 222, 0.8);
          cursor: pointer;
          transition: all 0.3s ease;
          display: block;
        }

        .image-carousel-container .carousel-dot:hover {
          background: rgba(222, 222, 222, 0.8);
          transform: scale(1.2);
        }

        /* Active dot and slide positioning */
        <%= for i <- 0..(@image_count - 1) do %>
        .image-carousel-container input#slide-<%= @id %>-<%= i %>:checked ~ .carousel-wrapper .carousel-slides {
          transform: translateX(calc(-100% * <%= i %> / <%= @image_count %>));
        }

        .image-carousel-container input#slide-<%= @id %>-<%= i %>:checked ~ .carousel-wrapper .carousel-dots label[for="slide-<%= @id %>-<%= i %>"] .carousel-dot {
          background: rgba(255, 255, 255, 1);
          border-color: rgba(255, 255, 255, 1);
          transform: scale(1.3);
        }

        /* Show correct navigation buttons for each slide */
        .image-carousel-container input#slide-<%= @id %>-<%= i %>:checked ~ .carousel-wrapper .carousel-nav.prev[for="slide-<%= @id %>-<%= rem(i - 1 + @image_count, @image_count) %>"],
        .image-carousel-container input#slide-<%= @id %>-<%= i %>:checked ~ .carousel-wrapper .carousel-nav.next[for="slide-<%= @id %>-<%= rem(i + 1, @image_count) %>"] {
          display: flex !important;
          opacity: 0;
        }

        .image-carousel-container input#slide-<%= @id %>-<%= i %>:checked ~ .carousel-wrapper:hover .carousel-nav.prev[for="slide-<%= @id %>-<%= rem(i - 1 + @image_count, @image_count) %>"],
        .image-carousel-container input#slide-<%= @id %>-<%= i %>:checked ~ .carousel-wrapper:hover .carousel-nav.next[for="slide-<%= @id %>-<%= rem(i + 1, @image_count) %>"] {
          opacity: 1;
        }
        <% end %>

        /* Responsive adjustments */
        @media (max-width: 768px) {
          .image-carousel-container .carousel-nav {
            width: 2.5rem;
            height: 2.5rem;
          }

          .image-carousel-container .carousel-nav svg {
            width: 1.25rem;
            height: 1.25rem;
          }

          .image-carousel-container .carousel-nav.prev {
            left: 0.5rem;
          }

          .image-carousel-container .carousel-nav.next {
            right: 0.5rem;
          }
        }
      </style>

      <input type="radio" name={"carousel-#{@id}"} id={"slide-#{@id}-0"} checked />
      <%= for i <- 1..(@image_count - 1)//1 do %>
        <input type="radio" name={"carousel-#{@id}"} id={"slide-#{@id}-#{i}"} />
      <% end %>

      <div class="carousel-wrapper">
        <div class="carousel-slides">
          <%= for {image, index} <- Enum.with_index(@images) do %>
            <div class="carousel-slide">
              <img
                src={image[:src] || image["src"]}
                alt={image[:alt] || image["alt"] || "Cabin image #{index + 1}"}
              />
            </div>
          <% end %>
        </div>
        <!-- Overlay layer - only shown when overlay slot is provided -->
        <%= if @has_overlay do %>
          <div class="carousel-overlay"></div>
          <div class="carousel-overlay-content">
            <%= render_slot(@overlay) %>
          </div>
        <% end %>
        <!-- Navigation buttons - one set for each possible slide state -->
        <%= for i <- 0..(@image_count - 1) do %>
          <label
            for={"slide-#{@id}-#{rem(i - 1 + @image_count, @image_count)}"}
            class="carousel-nav prev"
            aria-label="Previous image"
          >
            <svg
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
              xmlns="http://www.w3.org/2000/svg"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M15 19l-7-7 7-7"
              />
            </svg>
          </label>
          <label
            for={"slide-#{@id}-#{rem(i + 1, @image_count)}"}
            class="carousel-nav next"
            aria-label="Next image"
          >
            <svg
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
              xmlns="http://www.w3.org/2000/svg"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M9 5l7 7-7 7"
              />
            </svg>
          </label>
        <% end %>
        <!-- Dots navigation -->
        <div class="carousel-dots">
          <%= for i <- 0..(@image_count - 1) do %>
            <label for={"slide-#{@id}-#{i}"} aria-label={"Go to slide #{i + 1}"}>
              <span class="carousel-dot"></span>
            </label>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
