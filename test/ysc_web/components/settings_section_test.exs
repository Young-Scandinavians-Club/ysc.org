defmodule YscWeb.Components.SettingsSectionTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.CoreComponents

  describe "settings_section/1" do
    test "renders the shared settings card chrome, title, and body" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.settings_section id="passkeys-section" title="Passkeys">
          <p>A passkey is a passwordless way to sign in.</p>
        </.settings_section>
        """)

      assert html =~ ~s(id="passkeys-section")
      assert html =~ "rounded-sm border border-zinc-100 py-4 px-4 space-y-4"
      assert html =~ "text-zinc-900 text-xl type-subhead"
      assert html =~ "Passkeys"
      assert html =~ "A passkey is a passwordless way to sign in."
      refute html =~ "text-zinc-500 font-normal text-sm ml-2"
    end

    test "appends a muted count after the title when given" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.settings_section title="Family Members" count={3}>
          <p>People on your family membership.</p>
        </.settings_section>
        """)

      assert html =~ "Family Members"
      assert html =~ "text-zinc-500 font-normal text-sm ml-2"
      assert html =~ "(3)"
      assert html =~ "People on your family membership."
    end

    test "renders a zero count and omits the span when count is nil" do
      assigns = %{}

      with_zero =
        rendered_to_string(~H"""
        <.settings_section title="Pending Invitations" count={0}>
          <p>None yet.</p>
        </.settings_section>
        """)

      without_count =
        rendered_to_string(~H"""
        <.settings_section title="Email">
          <p>Change your email.</p>
        </.settings_section>
        """)

      assert with_zero =~ "(0)"
      refute without_count =~ "text-zinc-500 font-normal text-sm ml-2"
    end

    test "merges extra classes onto the section container" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.settings_section title="Billing Address" class="mt-4">
          <p>Street and city.</p>
        </.settings_section>
        """)

      assert html =~ "mt-4"
      assert html =~ "rounded-sm border border-zinc-100"
    end
  end
end
