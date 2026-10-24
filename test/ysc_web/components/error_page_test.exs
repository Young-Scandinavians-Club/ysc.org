defmodule YscWeb.Components.ErrorPageTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.CoreComponents

  describe "error_page/1" do
    test "renders shared photo-hero chrome, logo, copy, home action, and image" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.error_page
          logo_id="error-404-home-logo"
          status={404}
          title="Page not found"
          class="bg-[#fcf9ec]"
          image="/images/lost_tomte.webp"
          image_alt="404 Lost Tomte"
        >
          The page you're looking for doesn't exist or has been moved.
        </.error_page>
        """)

      assert html =~ "w-full"
      assert html =~ "h-full"
      assert html =~ "bg-[#fcf9ec]"
      assert html =~ "min-h-screen"
      assert html =~ "max-w-5xl"
      assert html =~ "gap-7"
      assert html =~ "md:gap-12"
      assert html =~ "type-display"
      assert html =~ "type-title"
      assert html =~ ~s(id="error-404-home-logo")
      assert html =~ ~s(href="/")
      assert html =~ ~s(aria-label="Young Scandinavians Club home")
      assert html =~ "404"
      assert html =~ "Page not found"

      assert html =~
               "The page you're looking for doesn't exist or has been moved."

      assert html =~ "Go back home"
      assert html =~ ~s(src="/images/lost_tomte.webp")
      assert html =~ ~s(alt="404 Lost Tomte")
      refute html =~ ~s(id="home-logo-link")
    end

    test "forwards a wrapper id and extra background classes" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.error_page
          id="error-500-page"
          logo_id="error-500-home-logo"
          status={500}
          title="Something went wrong"
          class="bg-[#f9efdf]"
          image="/images/404_fika.webp"
          image_alt="500 Fika"
        >
          Please try again in a few minutes.
        </.error_page>
        """)

      assert html =~ ~s(id="error-500-page")
      assert html =~ ~s(id="error-500-home-logo")
      assert html =~ "bg-[#f9efdf]"
      assert html =~ "500"
      assert html =~ "Something went wrong"
      assert html =~ "Please try again in a few minutes."
      assert html =~ ~s(src="/images/404_fika.webp")
      assert html =~ ~s(alt="500 Fika")
    end
  end
end
