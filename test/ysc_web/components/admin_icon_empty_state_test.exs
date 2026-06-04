defmodule YscWeb.AdminIconEmptyStateTest do
  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.AdminComponents

  describe "admin_icon_empty_state/1" do
    test "renders default variant with icon, title, and description" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_icon_empty_state
          id="no-sessions"
          icon="hero-qr-code"
          title="No scan sessions yet"
          description="Start a new scan session to begin."
        />
        """)

      assert html =~ ~s(id="no-sessions")
      assert html =~ "hero-qr-code"
      assert html =~ "py-16"
      assert html =~ "No scan sessions yet"
      assert html =~ "Start a new scan session to begin."
      assert html =~ "text-lg font-medium"
    end

    test "renders compact variant" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_icon_empty_state
          variant={:compact}
          icon="hero-magnifying-glass"
          title="No members found"
          description="Try a different name or email address"
        />
        """)

      assert html =~ "py-10"
      assert html =~ "hero-magnifying-glass"
      assert html =~ "font-medium"
      assert html =~ "text-zinc-400"
      assert html =~ "No members found"
    end

    test "renders dashed variant with custom padding and icon size" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_icon_empty_state
          variant={:dashed}
          icon="hero-check-circle"
          title="No pending applications"
          class="py-8"
          icon_class="w-7 h-7 text-zinc-200 mx-auto mb-2"
        />
        """)

      assert html =~ "border-dashed border-zinc-100"
      assert html =~ "py-8"
      assert html =~ "w-7 h-7"
      assert html =~ "text-sm text-zinc-400"
      assert html =~ "No pending applications"
    end

    test "renders action slot below description" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_icon_empty_state
          icon="hero-photo"
          title="No images yet"
          description="Upload your first image"
        >
          <:action>
            <button type="button" id="upload-cta">Upload</button>
          </:action>
        </.admin_icon_empty_state>
        """)

      assert html =~ ~s(id="upload-cta")
      assert html =~ "Upload"
      assert html =~ "mt-4"
    end

    test "omits description paragraph when description is nil" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_icon_empty_state
          variant={:dashed}
          icon="hero-calendar"
          title="No upcoming events"
        />
        """)

      refute html =~ "text-sm mt-1"
    end
  end
end
