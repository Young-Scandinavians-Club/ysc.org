defmodule YscWeb.Components.GalleryComponentTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ysc.Media.Image
  alias YscWeb.Components.GalleryComponent

  describe "render/1" do
    test "renders empty gallery with no images" do
      assigns = %{
        id: "test-gallery",
        images: []
      }

      html = render_component(GalleryComponent, assigns)

      assert html =~ "id=\"test-gallery\""
      assert html =~ "phx-update=\"stream\""
      refute html =~ "<button"
    end

    test "renders gallery with single image" do
      image = %Image{
        id: "01KG3TEST123",
        raw_image_path: "/uploads/test.jpg",
        title: "Test Image",
        alt_text: "Test alt text",
        blur_hash: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
      }

      assigns = %{
        id: "test-gallery",
        images: [{"image-1", image}]
      }

      html = render_component(GalleryComponent, assigns)

      assert html =~ "id=\"test-gallery\""
      assert html =~ "Test Image"
      assert html =~ "/uploads/test.jpg"
      assert html =~ "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
    end

    test "renders gallery with multiple images" do
      images = [
        {"image-1",
         %Image{
           id: "01KG3TEST123",
           raw_image_path: "/uploads/test1.jpg",
           title: "Image One",
           blur_hash: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
         }},
        {"image-2",
         %Image{
           id: "01KG3TEST456",
           raw_image_path: "/uploads/test2.jpg",
           title: "Image Two",
           blur_hash: "LKO2?U%2Tw=w]~RBVZRi};RPxuwH"
         }},
        {"image-3",
         %Image{
           id: "01KG3TEST789",
           raw_image_path: "/uploads/test3.jpg",
           title: "Image Three",
           blur_hash: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
         }}
      ]

      assigns = %{
        id: "test-gallery",
        images: images
      }

      html = render_component(GalleryComponent, assigns)

      assert html =~ "Image One"
      assert html =~ "Image Two"
      assert html =~ "Image Three"
      assert html =~ "/uploads/test1.jpg"
      assert html =~ "/uploads/test2.jpg"
      assert html =~ "/uploads/test3.jpg"
    end

    test "displays image title when present" do
      image = %Image{
        id: "01KG3TEST123",
        raw_image_path: "/uploads/test.jpg",
        title: "Sunset Photo",
        alt_text: nil
      }

      assigns = %{
        id: "test-gallery",
        images: [{"image-1", image}]
      }

      html = render_component(GalleryComponent, assigns)

      assert html =~ "Sunset Photo"
    end

    test "displays alt text when title is nil" do
      image = %Image{
        id: "01KG3TEST123",
        raw_image_path: "/uploads/test.jpg",
        title: nil,
        alt_text: "Beautiful sunset over the lake"
      }

      assigns = %{
        id: "test-gallery",
        images: [{"image-1", image}]
      }

      html = render_component(GalleryComponent, assigns)

      assert html =~ "Beautiful sunset over the lake"
    end

    test "does not show overlay when both title and alt_text are nil" do
      image = %Image{
        id: "01KG3TEST123",
        raw_image_path: "/uploads/test.jpg",
        title: nil,
        alt_text: nil
      }

      assigns = %{
        id: "test-gallery",
        images: [{"image-1", image}]
      }

      html = render_component(GalleryComponent, assigns)

      # Overlay div should not be present when both are nil
      refute html =~ ~r/group-hover:block.*bg-gradient-to-t/
    end

    test "uses default blur hash when image blur_hash is nil" do
      image = %Image{
        id: "01KG3TEST123",
        raw_image_path: "/uploads/test.jpg",
        title: "Test",
        blur_hash: nil
      }

      assigns = %{
        id: "test-gallery",
        images: [{"image-1", image}]
      }

      html = render_component(GalleryComponent, assigns)

      # Should use default blur hash
      assert html =~ "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
    end

    test "uses custom blur hash when provided" do
      image = %Image{
        id: "01KG3TEST123",
        raw_image_path: "/uploads/test.jpg",
        title: "Test",
        blur_hash: "LKO2?U%2Tw=w]~RBVZRi};RPxuwH"
      }

      assigns = %{
        id: "test-gallery",
        images: [{"image-1", image}]
      }

      html = render_component(GalleryComponent, assigns)

      assert html =~ "LKO2?U%2Tw=w]~RBVZRi};RPxuwH"
    end
  end

  describe "image path selection" do
    test "uses thumbnail_path when available" do
      image = %Image{
        id: "01KG3TEST123",
        raw_image_path: "/uploads/original.jpg",
        optimized_image_path: "/uploads/optimized.jpg",
        thumbnail_path: "/uploads/thumb.jpg",
        title: "Test"
      }

      assigns = %{
        id: "test-gallery",
        images: [{"image-1", image}]
      }

      html = render_component(GalleryComponent, assigns)

      assert html =~ "/uploads/thumb.jpg"
      refute html =~ "/uploads/optimized.jpg"
      refute html =~ "/uploads/original.jpg"
    end

    test "falls back to raw_image_path when thumbnail is nil, regardless of optimized" do
      image = %Image{
        id: "01KG3TEST123",
        raw_image_path: "/uploads/original.jpg",
        optimized_image_path: "/uploads/optimized.jpg",
        thumbnail_path: nil,
        title: "Test"
      }

      assigns = %{
        id: "test-gallery",
        images: [{"image-1", image}]
      }

      html = render_component(GalleryComponent, assigns)

      # Due to pattern matching order, when thumbnail is nil, uses raw_image_path
      assert html =~ "/uploads/original.jpg"
      refute html =~ "/uploads/optimized.jpg"
    end
  end

  describe "interactive elements" do
    test "each image has a clickable button" do
      image = %Image{
        id: "01KG3TEST123",
        raw_image_path: "/uploads/test.jpg",
        title: "Test Image"
      }

      assigns = %{
        id: "test-gallery",
        images: [{"image-1", image}]
      }

      html = render_component(GalleryComponent, assigns)

      assert html =~ "<button"
      assert html =~ "phx-click"
    end

    test "clicking image navigates to admin media upload page" do
      image = %Image{
        id: "01KG3TEST123",
        raw_image_path: "/uploads/test.jpg",
        title: "Test Image"
      }

      assigns = %{
        id: "test-gallery",
        images: [{"image-1", image}]
      }

      html = render_component(GalleryComponent, assigns)

      assert html =~ "/admin/media/upload/01KG3TEST123"
    end
  end

  describe "styling and layout" do
    test "uses grid layout with responsive columns" do
      assigns = %{
        id: "test-gallery",
        images: []
      }

      html = render_component(GalleryComponent, assigns)

      assert html =~ "grid"
      assert html =~ "grid-cols-2"
      assert html =~ "md:grid-cols-3"
      assert html =~ "xl:grid-cols-4"
    end

    test "applies hover effects to images" do
      image = %Image{
        id: "01KG3TEST123",
        raw_image_path: "/uploads/test.jpg",
        title: "Test"
      }

      assigns = %{
        id: "test-gallery",
        images: [{"image-1", image}]
      }

      html = render_component(GalleryComponent, assigns)

      assert html =~ "group"
      assert html =~ "hover:border-zinc-400"
      assert html =~ "group-hover:opacity-100"
    end

    test "uses blur hash canvas for loading placeholder" do
      image = %Image{
        id: "01KG3TEST123",
        raw_image_path: "/uploads/test.jpg",
        title: "Test",
        blur_hash: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
      }

      assigns = %{
        id: "test-gallery",
        images: [{"image-1", image}]
      }

      html = render_component(GalleryComponent, assigns)

      assert html =~ "<canvas"
      assert html =~ "phx-hook=\"BlurHashCanvas\""
      assert html =~ "blur-hash-image-01KG3TEST123"
    end

    test "uses blur hash image hook for progressive loading" do
      image = %Image{
        id: "01KG3TEST123",
        raw_image_path: "/uploads/test.jpg",
        title: "Test"
      }

      assigns = %{
        id: "test-gallery",
        images: [{"image-1", image}]
      }

      html = render_component(GalleryComponent, assigns)

      assert html =~ "phx-hook=\"BlurHashImage\""
      assert html =~ "image-01KG3TEST123"
    end
  end

  describe "accessibility" do
    test "includes alt text for images" do
      image = %Image{
        id: "01KG3TEST123",
        raw_image_path: "/uploads/test.jpg",
        alt_text: "Mountain landscape"
      }

      assigns = %{
        id: "test-gallery",
        images: [{"image-1", image}]
      }

      html = render_component(GalleryComponent, assigns)

      assert html =~ ~s(alt="Mountain landscape")
    end

    test "uses title as alt when alt_text is nil" do
      image = %Image{
        id: "01KG3TEST123",
        raw_image_path: "/uploads/test.jpg",
        title: "Beautiful Sunset",
        alt_text: nil
      }

      assigns = %{
        id: "test-gallery",
        images: [{"image-1", image}]
      }

      html = render_component(GalleryComponent, assigns)

      assert html =~ ~s(alt="Beautiful Sunset")
    end

    test "uses generic alt text when both title and alt_text are nil" do
      image = %Image{
        id: "01KG3TEST123",
        raw_image_path: "/uploads/test.jpg",
        title: nil,
        alt_text: nil
      }

      assigns = %{
        id: "test-gallery",
        images: [{"image-1", image}]
      }

      html = render_component(GalleryComponent, assigns)

      assert html =~ ~s(alt="Image")
    end
  end
end
