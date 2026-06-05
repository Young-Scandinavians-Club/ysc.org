defmodule YscWeb.Components.StaffContentPreviewBannerTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.CoreComponents

  describe "staff_content_preview_banner/1" do
    test "renders event preview banner" do
      assigns = %{}

      heex = ~H"""
      <.staff_content_preview_banner id="event-content-preview-banner" kind={:event} />
      """

      html = rendered_to_string(heex)

      assert html =~ ~s|id="event-content-preview-banner"|
      assert html =~ "bg-amber-50"
      assert html =~ "border-amber-200"
      assert html =~ "hero-eye"
      assert html =~ "Staff preview — this event is not published yet."
    end

    test "renders article preview banner" do
      assigns = %{}

      heex = ~H"""
      <.staff_content_preview_banner id="post-content-preview-banner" kind={:article} />
      """

      html = rendered_to_string(heex)

      assert html =~ ~s|id="post-content-preview-banner"|
      assert html =~ "Staff preview — this article is not published yet."
    end
  end
end
