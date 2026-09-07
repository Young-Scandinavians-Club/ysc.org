defmodule YscWeb.Components.AutosaveStatusTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.CoreComponents

  describe "autosave_status/1" do
    test "renders spinning Saving copy while a write is in flight" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.autosave_status id="post-editor-autosave-status" saving?={true} />
        """)

      assert html =~ ~s(id="post-editor-autosave-status")
      assert html =~ "hero-arrow-path"
      assert html =~ "animate-spin"
      assert html =~ "Saving"
      assert html =~ ~s(role="status")
      assert html =~ ~s(aria-live="polite")
      refute html =~ "Saved"
    end

    test "idle state keeps the status slot without announcing Saving" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.autosave_status id="idle-status" saving?={false} />
        """)

      assert html =~ ~s(id="idle-status")
      refute html =~ "Saving"
      refute html =~ "hero-arrow-path"
    end

    test "renders screen-reader idle copy when provided" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.autosave_status
          id="expense-report-autosave-status"
          saving?={false}
          idle_label="Draft not started"
        />
        """)

      assert html =~ "sr-only"
      assert html =~ "Draft not started"
    end

    test "shows saved_label with a check icon when saved?" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.autosave_status
          id="expense-saved"
          saving?={false}
          saved?={true}
          saved_label="All changes saved"
        />
        """)

      assert html =~ "All changes saved"
      assert html =~ "hero-check"
      refute html =~ "Saving"
      refute html =~ "hero-arrow-path"
    end

    test "formats saved_at as Saved time with a confirmation dot" do
      assigns = %{saved_at: ~U[2026-09-06 15:04:00Z]}

      html =
        rendered_to_string(~H"""
        <.autosave_status
          id="newsletter-saved"
          saving?={false}
          saved_at={@saved_at}
        />
        """)

      assert html =~ "Saved 03:04 PM"
      assert html =~ "bg-emerald-400"
      refute html =~ "hero-check"
      refute html =~ "Saving"
    end

    test "saving? takes precedence over saved_at" do
      assigns = %{saved_at: ~U[2026-09-06 15:04:00Z]}

      html =
        rendered_to_string(~H"""
        <.autosave_status saving?={true} saved_at={@saved_at} />
        """)

      assert html =~ "Saving"
      refute html =~ "Saved 03:04 PM"
    end

    test "renders nothing when readonly" do
      assigns = %{saved_at: ~U[2026-09-06 15:04:00Z]}

      html =
        rendered_to_string(~H"""
        <.autosave_status
          id="readonly-status"
          saving?={true}
          saved_at={@saved_at}
          readonly?={true}
        />
        """)

      assert html == ""
    end

    test "sm size uses the post-editor type scale" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.autosave_status saving?={true} size={:sm} class="self-center" />
        """)

      assert html =~ "text-sm text-zinc-600"
      assert html =~ "self-center"
      refute html =~ "text-xs text-zinc-500"
    end
  end
end
