defmodule YscWeb.Components.DocumentDownload do
  @moduledoc """
  File-download cards and annual-meeting year sections used on the
  member-facing financials page (and any future document index).
  """
  use Phoenix.Component

  import YscWeb.CoreComponents, only: [icon: 1]

  @kind_icon %{
    summary: "hero-document-chart-bar",
    report: "hero-document-chart-bar",
    minutes: "hero-document-text",
    slides: "hero-document-chart-bar"
  }

  @kind_tone %{
    summary: "bg-red-100 text-red-600",
    report: "bg-blue-100 text-blue-600",
    minutes: "bg-green-100 text-green-600",
    slides: "bg-orange-100 text-orange-600"
  }

  @doc """
  Linked card for a downloadable file (PDF, DOCX, PPTX).

  `kind` picks the icon tile color: `:summary` (red), `:report` (blue),
  `:minutes` (green), `:slides` (orange). Override `icon` when the default
  heroicon for that kind is wrong.

  ## Examples

      <.document_download_card
        id="financials-2026-summary"
        href={~p"/annual_meetings/2026/report.pdf"}
        title="Financials Summary 2025"
        meta="PDF • 70K"
        kind={:summary}
      />
  """
  attr :id, :string, default: nil
  attr :href, :string, required: true
  attr :title, :string, required: true

  attr :meta, :string,
    required: true,
    doc: "File type and size, e.g. `PDF • 70K`"

  attr :kind, :atom,
    default: :report,
    values: [:summary, :report, :minutes, :slides]

  attr :icon, :string,
    default: nil,
    doc: "Heroicon name; defaults from `kind`"

  attr :class, :any, default: nil

  def document_download_card(assigns) do
    kind = assigns.kind

    assigns =
      assign(assigns,
        resolved_icon: assigns.icon || Map.fetch!(@kind_icon, kind),
        tone_class: Map.fetch!(@kind_tone, kind)
      )

    ~H"""
    <.link
      id={@id}
      href={@href}
      target="_blank"
      rel="noopener noreferrer"
      class={[
        "group flex items-center p-4 border border-zinc-100 rounded-lg hover:border-blue-500 hover:bg-blue-50 transition",
        @class
      ]}
    >
      <div class={["p-3 rounded-lg mr-4 shrink-0", @tone_class]}>
        <.icon name={@resolved_icon} class="w-6 h-6" />
      </div>
      <div class="min-w-0">
        <div class="font-bold text-zinc-900 group-hover:text-blue-700">
          {@title}
        </div>
        <div class="text-xs text-zinc-500 mt-1 type-eyebrow">
          {@meta}
        </div>
      </div>
    </.link>
    """
  end

  @doc """
  Year block wrapping a grid of `document_download_card/1` links.

  `:featured` is a standalone card with a dark heading (recent years).
  `:archive` is a padded inner block used inside the collapsible archive.

  ## Examples

      <.annual_meeting_section id="year-2026" title="2026 General Meeting">
        <.document_download_card title="Full Annual Report" ... />
      </.annual_meeting_section>

      <.annual_meeting_section
        id="year-2018"
        title="2018 General Meeting"
        variant={:archive}
      >
        <.document_download_card title="Financials Summary 2017" ... />
      </.annual_meeting_section>
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :variant, :atom, default: :featured, values: [:featured, :archive]
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def annual_meeting_section(%{variant: :archive} = assigns) do
    ~H"""
    <div id={@id} class={["p-6", @class]}>
      <h3 class="text-lg text-zinc-900 mb-4 type-subhead">{@title}</h3>
      <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  def annual_meeting_section(assigns) do
    ~H"""
    <section
      id={@id}
      class={[
        "bg-white border border-zinc-200 rounded-xl shadow-xs overflow-hidden",
        @class
      ]}
    >
      <div class="bg-zinc-900 px-6 py-4">
        <h2 class="text-white text-xl m-0 type-subhead">{@title}</h2>
      </div>
      <div class="p-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end
end
