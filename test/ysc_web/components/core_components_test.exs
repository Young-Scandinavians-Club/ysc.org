defmodule YscWeb.CoreComponentsTest do
  use YscWeb.ConnCase, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]
  import YscWeb.CoreComponents

  describe "upload_dropzone_empty_state/1" do
    test "renders default placeholder copy and formats" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.upload_dropzone_empty_state />
        """)

      assert html =~ "hero-cloud-arrow-up"
      assert html =~ "Click to upload"
      assert html =~ "drag and drop"
      assert html =~ "SVG, PNG, JPG, JPEG or GIF"
      assert html =~ "pt-5 pb-6"
      assert html =~ "mb-4"
    end

    test "compact size uses tighter spacing" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.upload_dropzone_empty_state
          size={:compact}
          formats="PNG, JPG, JPEG, GIF or WebP"
        />
        """)

      assert html =~ "pt-3 pb-4"
      assert html =~ "mb-3"
      assert html =~ "PNG, JPG, JPEG, GIF or WebP"
      refute html =~ "SVG, PNG, JPG, JPEG or GIF"
    end

    test "merges custom class onto container" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.upload_dropzone_empty_state class="custom-dropzone" id="drop-hint" />
        """)

      assert html =~ ~s(id="drop-hint")
      assert html =~ "custom-dropzone"
    end
  end

  describe "upload_dropzone_label_class/1" do
    test "returns default dashed label classes" do
      classes = upload_dropzone_label_class()

      assert Enum.join(classes, " ") =~ "border-dashed"
      assert Enum.join(classes, " ") =~ "min-h-72"
    end

    test "accepts custom min height" do
      classes = upload_dropzone_label_class(min_height: "min-h-52")

      assert Enum.join(classes, " ") =~ "min-h-52"
      refute Enum.join(classes, " ") =~ "min-h-72"
    end
  end
end
