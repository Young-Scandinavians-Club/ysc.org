defmodule YscWeb.ModalTitleComponentsTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.CoreComponents

  describe "modal_title/1" do
    test "renders default modal heading styles" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.modal_title>Verify Your Phone Number</.modal_title>
        """)

      assert html =~ "<h2"
      assert html =~ "text-2xl font-semibold leading-8 text-zinc-800 mb-6"
      assert html =~ "Verify Your Phone Number"
    end

    test "renders optional id for aria-labelledby wiring" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.modal_title id="verify-phone-modal-title">Verify</.modal_title>
        """)

      assert html =~ ~s(id="verify-phone-modal-title")
    end

    test "merges custom classes onto the default styles" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.modal_title class="mb-4">Custom spacing</.modal_title>
        """)

      assert html =~ "text-2xl font-semibold leading-8 text-zinc-800 mb-6"
      assert html =~ "mb-4"
    end
  end
end
