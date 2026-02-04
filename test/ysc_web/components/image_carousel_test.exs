defmodule YscWeb.Components.ImageCarouselTest do
  use YscWeb.ConnCase, async: true

  require Phoenix.LiveViewTest
  alias YscWeb.Components.ImageCarousel

  defp render_carousel(assigns) do
    assigns = Map.put_new(assigns, :class, "")
    assigns = Map.put_new(assigns, :overlay, [])

    # Render as a function component
    Phoenix.LiveViewTest.render_component(
      &ImageCarousel.image_carousel/1,
      assigns
    )
  end

  describe "image_carousel/1" do
    test "renders carousel with single image" do
      html =
        render_carousel(%{
          id: "test-carousel",
          images: [
            %{src: "/images/test1.jpg", alt: "Test image 1"}
          ]
        })

      assert html =~ "image-carousel-container"
      assert html =~ "/images/test1.jpg"
      assert html =~ "Test image 1"
    end

    test "renders carousel with multiple images" do
      html =
        render_carousel(%{
          id: "test-carousel",
          images: [
            %{src: "/images/test1.jpg", alt: "Test image 1"},
            %{src: "/images/test2.jpg", alt: "Test image 2"},
            %{src: "/images/test3.jpg", alt: "Test image 3"}
          ]
        })

      assert html =~ "/images/test1.jpg"
      assert html =~ "/images/test2.jpg"
      assert html =~ "/images/test3.jpg"
      assert html =~ "Test image 1"
      assert html =~ "Test image 2"
      assert html =~ "Test image 3"
    end

    test "uses custom ID for carousel" do
      html =
        render_carousel(%{
          id: "my-custom-carousel",
          images: [
            %{src: "/images/test.jpg", alt: "Test"}
          ]
        })

      assert html =~ "my-custom-carousel"
      assert html =~ ~s(id="slide-my-custom-carousel-0")
    end

    test "applies additional CSS classes" do
      html =
        render_carousel(%{
          id: "test-carousel",
          images: [%{src: "/images/test.jpg", alt: "Test"}],
          class: "my-8 custom-class"
        })

      assert html =~ "my-8"
      assert html =~ "custom-class"
    end

    test "works with atom keys for images" do
      html =
        render_carousel(%{
          id: "test-carousel",
          images: [
            %{src: "/images/test.jpg", alt: "Test with atoms"}
          ]
        })

      assert html =~ "/images/test.jpg"
      assert html =~ "Test with atoms"
    end

    test "works with string keys for images" do
      html =
        render_carousel(%{
          id: "test-carousel",
          images: [
            %{"src" => "/images/test.jpg", "alt" => "Test with strings"}
          ]
        })

      assert html =~ "/images/test.jpg"
      assert html =~ "Test with strings"
    end
  end

  describe "navigation elements" do
    test "includes radio buttons for slide navigation" do
      html =
        render_carousel(%{
          id: "test-carousel",
          images: [
            %{src: "/images/test1.jpg", alt: "Test 1"},
            %{src: "/images/test2.jpg", alt: "Test 2"}
          ]
        })

      assert html =~ ~s(type="radio")
      assert html =~ ~s(name="carousel-test-carousel")
      assert html =~ ~s(id="slide-test-carousel-0")
      assert html =~ ~s(id="slide-test-carousel-1")
    end

    test "first slide is checked by default" do
      html =
        render_carousel(%{
          id: "test-carousel",
          images: [
            %{src: "/images/test1.jpg", alt: "Test 1"},
            %{src: "/images/test2.jpg", alt: "Test 2"}
          ]
        })

      # First radio button should have checked attribute
      assert html =~ ~r/id="slide-test-carousel-0"\s+checked/
    end

    test "includes navigation arrows" do
      html =
        render_carousel(%{
          id: "test-carousel",
          images: [
            %{src: "/images/test1.jpg", alt: "Test 1"},
            %{src: "/images/test2.jpg", alt: "Test 2"}
          ]
        })

      assert html =~ "carousel-nav prev"
      assert html =~ "carousel-nav next"
      assert html =~ "Previous image"
      assert html =~ "Next image"
    end

    test "includes dot navigation indicators" do
      html =
        render_carousel(%{
          id: "test-carousel",
          images: [
            %{src: "/images/test1.jpg", alt: "Test 1"},
            %{src: "/images/test2.jpg", alt: "Test 2"},
            %{src: "/images/test3.jpg", alt: "Test 3"}
          ]
        })

      assert html =~ "carousel-dots"
      assert html =~ "carousel-dot"
      assert html =~ "Go to slide 1"
      assert html =~ "Go to slide 2"
      assert html =~ "Go to slide 3"
    end
  end

  describe "image handling" do
    test "uses default alt text when not provided" do
      html =
        render_carousel(%{
          id: "test-carousel",
          images: [
            %{src: "/images/test1.jpg"},
            %{src: "/images/test2.jpg"}
          ]
        })

      assert html =~ "Cabin image 1"
      assert html =~ "Cabin image 2"
    end

    test "handles images with empty alt text" do
      html =
        render_carousel(%{
          id: "test-carousel",
          images: [
            %{src: "/images/test.jpg", alt: ""}
          ]
        })

      # Empty string is still considered provided, so component uses it as-is
      # Only nil triggers the default text
      assert html =~ ~s(alt="")
    end
  end

  describe "carousel structure" do
    test "includes carousel wrapper" do
      html =
        render_carousel(%{
          id: "test-carousel",
          images: [%{src: "/images/test.jpg", alt: "Test"}]
        })

      assert html =~ "carousel-wrapper"
      assert html =~ "carousel-slides"
      assert html =~ "carousel-slide"
    end

    test "each image is in its own slide container" do
      html =
        render_carousel(%{
          id: "test-carousel",
          images: [
            %{src: "/images/test1.jpg", alt: "Test 1"},
            %{src: "/images/test2.jpg", alt: "Test 2"}
          ]
        })

      # Look for the actual div elements, not the class name which appears in CSS too
      slide_count =
        html
        |> String.split(~r/<div class="carousel-slide">/)
        |> length()
        |> Kernel.-(1)

      assert slide_count == 2
    end
  end

  describe "CSS styling" do
    test "includes component-specific CSS" do
      html =
        render_carousel(%{
          id: "test-carousel",
          images: [%{src: "/images/test.jpg", alt: "Test"}]
        })

      assert html =~ "<style>"
      assert html =~ ".image-carousel-container"
      assert html =~ "transform:"
      assert html =~ "transition:"
    end

    test "includes responsive styles" do
      html =
        render_carousel(%{
          id: "test-carousel",
          images: [%{src: "/images/test.jpg", alt: "Test"}]
        })

      assert html =~ "@media"
      assert html =~ "max-width: 768px"
    end

    test "detects height class in custom class attribute" do
      html =
        render_carousel(%{
          id: "test-carousel",
          images: [%{src: "/images/test.jpg", alt: "Test"}],
          class: "h-96"
        })

      # Should include height-specific CSS
      assert html =~ "h-96"
    end

    test "uses default aspect ratio when no height class" do
      html =
        render_carousel(%{
          id: "test-carousel",
          images: [%{src: "/images/test.jpg", alt: "Test"}],
          class: "my-4"
        })

      assert html =~ "aspect-ratio"
      assert html =~ "16 / 9"
    end
  end

  describe "multiple carousels on same page" do
    test "carousels with different IDs don't interfere" do
      html1 =
        render_carousel(%{
          id: "carousel-1",
          images: [%{src: "/images/test1.jpg", alt: "Test 1"}]
        })

      html2 =
        render_carousel(%{
          id: "carousel-2",
          images: [%{src: "/images/test2.jpg", alt: "Test 2"}]
        })

      # Each carousel should have its own unique IDs
      assert html1 =~ "carousel-carousel-1"
      assert html2 =~ "carousel-carousel-2"
      refute html1 =~ "carousel-carousel-2"
      refute html2 =~ "carousel-carousel-1"
    end
  end

  describe "accessibility" do
    test "includes proper ARIA labels for navigation" do
      html =
        render_carousel(%{
          id: "test-carousel",
          images: [
            %{src: "/images/test1.jpg", alt: "Test 1"},
            %{src: "/images/test2.jpg", alt: "Test 2"}
          ]
        })

      assert html =~ ~s(aria-label="Previous image")
      assert html =~ ~s(aria-label="Next image")
      assert html =~ ~s(aria-label="Go to slide 1")
      assert html =~ ~s(aria-label="Go to slide 2")
    end

    test "includes alt text for all images" do
      html =
        render_carousel(%{
          id: "test-carousel",
          images: [
            %{src: "/images/test1.jpg", alt: "Mountain view"},
            %{src: "/images/test2.jpg", alt: "Lake scene"}
          ]
        })

      assert html =~ ~s(alt="Mountain view")
      assert html =~ ~s(alt="Lake scene")
    end
  end

  describe "edge cases" do
    test "handles carousel with many images" do
      images =
        for i <- 1..10 do
          %{src: "/images/test#{i}.jpg", alt: "Test #{i}"}
        end

      html =
        render_carousel(%{
          id: "test-carousel",
          images: images
        })

      # Should render all 10 images
      for i <- 1..10 do
        assert html =~ "/images/test#{i}.jpg"
        assert html =~ "Test #{i}"
      end
    end

    test "handles images with special characters in paths" do
      html =
        render_carousel(%{
          id: "test-carousel",
          images: [
            %{src: "/images/test (1).jpg", alt: "Test with spaces"},
            %{src: "/images/test-2024-01-01.jpg", alt: "Test with dashes"}
          ]
        })

      assert html =~ "/images/test (1).jpg"
      assert html =~ "/images/test-2024-01-01.jpg"
    end
  end
end
