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

  describe "at_glance_grid/1 and at_glance_stat/1" do
    test "renders responsive grid with blue accent stat tiles" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.at_glance_grid>
          <.at_glance_stat
            icon="🛏️"
            label="Capacity"
            value="17 Guests"
            detail="7 Bedrooms"
          />
        </.at_glance_grid>
        """)

      assert html =~ "grid grid-cols-2 lg:grid-cols-4 gap-4 mb-12"
      assert html =~ "hover:border-blue-200"
      assert html =~ "bg-blue-50"
      assert html =~ "Capacity"
      assert html =~ "17 Guests"
      assert html =~ "7 Bedrooms"
    end

    test "renders teal accent styling" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.at_glance_stat
          accent={:teal}
          icon="⚓"
          label="Dock"
          value="100-Foot Private"
          detail="Boat mooring & swimming"
        />
        """)

      assert html =~ "hover:border-teal-200"
      assert html =~ "bg-teal-50"
      assert html =~ "Dock"
      assert html =~ "100-Foot Private"
      assert html =~ "Boat mooring &amp; swimming"
    end

    test "omits detail line when not provided" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.at_glance_stat icon="🔥" label="Features" value="Wood Fireplace" />
        """)

      assert html =~ "Features"
      assert html =~ "Wood Fireplace"
      refute html =~ "text-xs text-zinc-500 text-center mt-1"
    end

    test "merges custom class onto stat tile" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.at_glance_stat
          icon="🛶"
          label="Summer"
          value="Kayaks"
          class="custom-stat"
        />
        """)

      assert html =~ "custom-stat"
    end
  end

  describe "oauth_button/1" do
    test "renders Google sign-in button with brand icon and phx-click" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.oauth_button
          provider={:google}
          label="Sign in with Google"
          phx-click="sign_in_with_google"
        />
        """)

      assert html =~ "Sign in with Google"
      assert html =~ ~s(phx-click="sign_in_with_google")
      assert html =~ ~s(fill="#4285F4")
      assert html =~ "border-zinc-300"
    end

    test "renders Facebook continue button with phx-target" do
      assigns = %{myself: "reauth-1"}

      html =
        rendered_to_string(~H"""
        <.oauth_button
          provider={:facebook}
          label="Continue with Facebook"
          phx-click="reauth_with_facebook"
          phx-target={@myself}
        />
        """)

      assert html =~ "Continue with Facebook"
      assert html =~ ~s(phx-click="reauth_with_facebook")
      assert html =~ ~s(phx-target="reauth-1")
      assert html =~ ~s(fill="#1877F2")
    end
  end

  describe "dropdown/1" do
    test "uses JS.toggle on button and hide on wrapper click-away" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.dropdown id="test-dropdown">
          <:button_block>Menu</:button_block>
          <ul>
            <li>Item</li>
          </ul>
        </.dropdown>
        """)

      document = LazyHTML.from_fragment(html)

      assert [_wrapper] =
               LazyHTML.filter(document, "div.relative[phx-click-away]")
               |> Enum.to_list()

      assert LazyHTML.filter(document, "div#test-dropdown[phx-click-away]")
             |> Enum.empty?()

      button = LazyHTML.query_by_id(document, "test-dropdownLink")
      assert LazyHTML.attribute(button, "aria-expanded") == ["false"]
      assert hd(LazyHTML.attribute(button, "phx-click")) =~ "toggle"
    end
  end

  describe "dropdown JS helpers" do
    test "toggle_dropdown/1 toggles visibility, aria-expanded, and dropdown-open class" do
      js = toggle_dropdown("#test-dropdown")
      ops = inspect(js.ops)

      assert ops =~ "aria-expanded"
      assert ops =~ "dropdown-open"
      assert ops =~ "toggle"
    end

    test "hide_dropdown/1 hides menu and resets aria-expanded and dropdown-open" do
      js = hide_dropdown("#test-dropdown")
      ops = inspect(js.ops)

      assert ops =~ "hide"
      assert ops =~ ~s|"aria-expanded", "false"|
      assert ops =~ "dropdown-open"
    end
  end
end
