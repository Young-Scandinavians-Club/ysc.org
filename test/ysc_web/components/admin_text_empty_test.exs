defmodule YscWeb.AdminTextEmptyTest do
  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.AdminComponents

  describe "admin_text_empty/1" do
    test "renders centered title, description, and id" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_text_empty
          id="ticket-list-empty"
          title="No tickets yet."
          description="Tickets will appear here once users start buying tickets."
        />
        """)

      assert html =~ ~s(id="ticket-list-empty")
      assert html =~ "text-center py-8 text-zinc-500"
      assert html =~ "font-semibold"
      assert html =~ "No tickets yet."
      assert html =~ "text-sm"
      assert html =~ "Tickets will appear here once users start buying tickets."
    end

    test "omits the description paragraph when description is nil" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_text_empty id="ticket-tiers-empty" title="No ticket tiers created yet." />
        """)

      assert html =~ ~s(id="ticket-tiers-empty")
      assert html =~ "No ticket tiers created yet."
      refute html =~ "text-sm"
    end

    test "merges extra class onto the wrapper" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_text_empty
          id="cancellation-refund-empty"
          class="mt-6"
          title="No ticket orders for this event."
          description="There's nothing to refund."
        />
        """)

      assert html =~ "mt-6"
      assert html =~ "No ticket orders for this event."
      assert html =~ "There&#39;s nothing to refund."
    end
  end
end
