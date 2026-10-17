defmodule YscWeb.Components.DocumentDownloadTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.CoreComponents

  describe "document_download_card/1" do
    test "renders title, meta, href, and default report styling" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.document_download_card
          id="financials-2026-report"
          href="/annual_meetings/2026/report.pdf"
          title="Full Annual Report"
          meta="PDF • 107K"
        />
        """)

      assert html =~ ~s(id="financials-2026-report")
      assert html =~ ~s(href="/annual_meetings/2026/report.pdf")
      assert html =~ ~s(target="_blank")
      assert html =~ ~s(rel="noopener noreferrer")
      assert html =~ "Full Annual Report"
      assert html =~ "PDF • 107K"
      assert html =~ "type-eyebrow"
      assert html =~ "bg-blue-100 text-blue-600"
      assert html =~ "hero-document-chart-bar"
    end

    test "applies summary, minutes, and slides tile colors" do
      assigns = %{}

      summary =
        rendered_to_string(~H"""
        <.document_download_card
          href="/summary.pdf"
          title="Summary"
          meta="PDF • 1K"
          kind={:summary}
        />
        """)

      minutes =
        rendered_to_string(~H"""
        <.document_download_card
          href="/minutes.pdf"
          title="Minutes"
          meta="PDF • 2K"
          kind={:minutes}
        />
        """)

      slides =
        rendered_to_string(~H"""
        <.document_download_card
          href="/slides.pptx"
          title="Slides"
          meta="PPTX • 3K"
          kind={:slides}
        />
        """)

      assert summary =~ "bg-red-100 text-red-600"
      assert summary =~ "hero-document-chart-bar"

      assert minutes =~ "bg-green-100 text-green-600"
      assert minutes =~ "hero-document-text"

      assert slides =~ "bg-orange-100 text-orange-600"
      assert slides =~ "hero-document-chart-bar"
    end

    test "lets callers override the heroicon" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.document_download_card
          href="/notes.txt"
          title="Notes"
          meta="TXT • 1K"
          kind={:minutes}
          icon="hero-document-text"
        />
        """)

      assert html =~ "hero-document-text"
      assert html =~ "bg-green-100 text-green-600"
    end
  end

  describe "annual_meeting_section/1" do
    test "featured variant renders a light h2 bar with badge, note and a document grid" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.annual_meeting_section
          id="year-2026"
          title="2026 General Meeting"
          badge="Latest"
          note="Reviews FY 2025"
        >
          <.document_download_card
            href="/report.pdf"
            title="Full Annual Report"
            meta="PDF • 107K"
          />
        </.annual_meeting_section>
        """)

      assert html =~ ~s(id="year-2026")
      assert html =~ "2026 General Meeting"
      assert html =~ "<h2"
      refute html =~ "<h3"
      refute html =~ "bg-zinc-900"
      assert html =~ "Latest"
      assert html =~ "Reviews FY 2025"
      assert html =~ "Full Annual Report"
      assert html =~ "sm:grid-cols-2 lg:grid-cols-3"
    end

    test "archive variant renders a padded h3 block without the heading bar" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.annual_meeting_section
          id="year-2018"
          title="2018 General Meeting"
          variant={:archive}
        >
          <.document_download_card
            href="/slides.pptx"
            title="Financials Presentation"
            meta="PPTX • 284K"
            kind={:slides}
          />
        </.annual_meeting_section>
        """)

      assert html =~ ~s(id="year-2018")
      assert html =~ "2018 General Meeting"
      assert html =~ "<h3"
      refute html =~ "<h2"
      refute html =~ "bg-zinc-50"
      assert html =~ "Financials Presentation"
      assert html =~ "bg-orange-100"
    end
  end
end
