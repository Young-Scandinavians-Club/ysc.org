defmodule YscWeb.BrandGuide do
  @moduledoc """
  Data behind the public brand page (`/brand`): logo downloads, the Nordic
  color palette and the web color scales.

  Colors mirror `assets/tailwind.config.js` and the Tailwind class names are
  written out in full so the JIT compiler keeps them.
  """

  use YscWeb, :verified_routes

  @doc """
  The official logo variants. Each slug maps to files in
  `priv/static/images/brand/logos/` named `ysc-logo-<slug>.<ext>`
  (svg, pdf, png at 2000 px, `-512.png`, and the Illustrator source `ai`).
  """
  def logo_variants do
    Enum.map(logo_variant_specs(), &with_files/1)
  end

  defp logo_variant_specs do
    [
      %{
        slug: "seal-white-center",
        name: "Seal, white center",
        surface: :light,
        description:
          "The default. A white center keeps the shield readable on any background."
      },
      %{
        slug: "seal-transparent-center",
        name: "Seal, see-through center",
        surface: :light,
        description:
          "Navy ring with a transparent center. Best on white or light backgrounds."
      },
      %{
        slug: "seal-white-ring",
        name: "Seal, white ring",
        surface: :dark,
        description:
          "White ring with navy lettering. For navy, dark or darkened photo backgrounds."
      },
      %{
        slug: "shield-white-text",
        name: "Shield, white lettering",
        surface: :dark,
        description:
          "No ring, white lettering. For dark backgrounds where a ring would feel heavy."
      },
      %{
        slug: "stacked-white-text",
        name: "Shield, name stacked",
        surface: :dark,
        description:
          "Name above and web address below in white. For wide, dark spaces like banners."
      }
    ]
  end

  defp with_files(%{slug: slug} = variant) do
    Map.merge(variant, %{
      preview: logo_href(slug, ".svg"),
      downloads: [
        %{label: "SVG", href: logo_href(slug, ".svg")},
        %{label: "PNG 2000 px", href: logo_href(slug, ".png")},
        %{label: "PNG 512 px", href: logo_href(slug, "-512.png")},
        %{label: "PDF", href: logo_href(slug, ".pdf")},
        %{label: "AI", href: logo_href(slug, ".ai")}
      ]
    })
  end

  defp logo_href(slug, suffix),
    do: ~p"/images/brand/logos/#{"ysc-logo-#{slug}#{suffix}"}"

  def logo_zip_path, do: ~p"/images/brand/logos/ysc-logos.zip"

  @doc "Files that must exist on disk for a logo variant, relative to `priv/static`."
  def logo_files(slug) do
    for ext <- ["svg", "pdf", "png", "ai"] do
      "images/brand/logos/ysc-logo-#{slug}.#{ext}"
    end ++ ["images/brand/logos/ysc-logo-#{slug}-512.png"]
  end

  @doc "Presentation template files, relative to `priv/static`."
  def template_files do
    [
      "documents/brand/YSC-presentation-template.potx",
      "documents/brand/YSC-presentation-template.pptx"
    ]
  end

  @doc """
  URL that opens a Google Slides "Make a copy" prompt for the template, or
  `nil` when no Slides file has been configured.
  """
  def google_slides_copy_url do
    case Application.get_env(:ysc, :brand_google_slides_template_id) do
      id when is_binary(id) and id != "" ->
        "https://docs.google.com/presentation/d/#{URI.encode(id)}/copy"

      _ ->
        nil
    end
  end

  def countries do
    [
      %{
        name: "Denmark",
        swatches: [
          %{
            label: "Red",
            hex: "#C8102E",
            bg: "bg-denmark-red",
            fg: "text-white"
          },
          %{label: "White", hex: "#FFFFFF", bg: "bg-white", fg: "text-zinc-900"}
        ]
      },
      %{
        name: "Finland",
        swatches: [
          %{
            label: "Blue",
            hex: "#002F6C",
            bg: "bg-finland-blue",
            fg: "text-white"
          },
          %{label: "White", hex: "#FFFFFF", bg: "bg-white", fg: "text-zinc-900"}
        ]
      },
      %{
        name: "Iceland",
        swatches: [
          %{
            label: "Blue",
            hex: "#02529C",
            bg: "bg-iceland-blue",
            fg: "text-white"
          },
          %{
            label: "Red",
            hex: "#DC1E35",
            bg: "bg-iceland-red",
            fg: "text-white"
          }
        ]
      },
      %{
        name: "Norway",
        swatches: [
          %{
            label: "Red",
            hex: "#BA0C2F",
            bg: "bg-norway-red",
            fg: "text-white"
          },
          %{
            label: "Blue",
            hex: "#00205B",
            bg: "bg-norway-blue",
            fg: "text-white"
          }
        ]
      },
      %{
        name: "Sweden",
        swatches: [
          %{
            label: "Blue",
            hex: "#005293",
            bg: "bg-sweden-blue",
            fg: "text-white"
          },
          %{
            label: "Yellow",
            hex: "#FECB00",
            bg: "bg-sweden-yellow",
            fg: "text-zinc-900"
          }
        ]
      }
    ]
  end

  @doc "Contrast of each color against white and ink text (WCAG 2.x)."
  def pairings do
    [
      %{
        name: "Denmark red",
        hex: "#C8102E",
        bg: "bg-denmark-red",
        white: {"5.9", :ok},
        ink: {"3.0", :no},
        use: "Background with white text"
      },
      %{
        name: "Finland blue",
        hex: "#002F6C",
        bg: "bg-finland-blue",
        white: {"12.9", :ok},
        ink: {"1.4", :no},
        use: "Background with white text"
      },
      %{
        name: "Iceland blue",
        hex: "#02529C",
        bg: "bg-iceland-blue",
        white: {"7.8", :ok},
        ink: {"2.3", :no},
        use: "Background with white text"
      },
      %{
        name: "Iceland red",
        hex: "#DC1E35",
        bg: "bg-iceland-red",
        white: {"4.9", :ok},
        ink: {"3.6", :large},
        use: "Labels and accents with white text"
      },
      %{
        name: "Norway red",
        hex: "#BA0C2F",
        bg: "bg-norway-red",
        white: {"6.6", :ok},
        ink: {"2.7", :no},
        use: "Labels and accents with white text"
      },
      %{
        name: "Norway blue",
        hex: "#00205B",
        bg: "bg-norway-blue",
        white: {"15.5", :ok},
        ink: {"1.1", :no},
        use: "Headings and dark backgrounds"
      },
      %{
        name: "Sweden blue",
        hex: "#005293",
        bg: "bg-sweden-blue",
        white: {"8.0", :ok},
        ink: {"2.2", :no},
        use: "Background with white text"
      },
      %{
        name: "Sweden yellow",
        hex: "#FECB00",
        bg: "bg-sweden-yellow",
        white: {"1.5", :no},
        ink: {"11.6", :ok},
        use: "Background with dark text, never as text on white"
      }
    ]
  end

  def blue_scale do
    [
      %{step: "50", hex: "#EEF8FF", bg: "bg-blue-50", fg: "text-zinc-900"},
      %{step: "100", hex: "#D8EFFF", bg: "bg-blue-100", fg: "text-zinc-900"},
      %{step: "200", hex: "#B9E3FF", bg: "bg-blue-200", fg: "text-zinc-900"},
      %{step: "300", hex: "#89D3FF", bg: "bg-blue-300", fg: "text-zinc-900"},
      %{step: "400", hex: "#52BBFF", bg: "bg-blue-400", fg: "text-zinc-900"},
      %{step: "500", hex: "#2A9DFF", bg: "bg-blue-500", fg: "text-white"},
      %{step: "600", hex: "#1381FD", bg: "bg-blue-600", fg: "text-white"},
      %{step: "700", hex: "#0C69E9", bg: "bg-blue-700", fg: "text-white"},
      %{step: "800", hex: "#1154BC", bg: "bg-blue-800", fg: "text-white"},
      %{step: "900", hex: "#144993", bg: "bg-blue-900", fg: "text-white"},
      %{step: "950", hex: "#112D5A", bg: "bg-blue-950", fg: "text-white"}
    ]
  end

  def zinc_scale do
    [
      %{step: "50", hex: "#FAFAFA", bg: "bg-zinc-50", fg: "text-zinc-900"},
      %{step: "100", hex: "#F4F4F5", bg: "bg-zinc-100", fg: "text-zinc-900"},
      %{step: "200", hex: "#E4E4E7", bg: "bg-zinc-200", fg: "text-zinc-900"},
      %{step: "300", hex: "#D4D4D8", bg: "bg-zinc-300", fg: "text-zinc-900"},
      %{step: "400", hex: "#A1A1AA", bg: "bg-zinc-400", fg: "text-zinc-900"},
      %{step: "500", hex: "#71717A", bg: "bg-zinc-500", fg: "text-white"},
      %{step: "600", hex: "#52525B", bg: "bg-zinc-600", fg: "text-white"},
      %{step: "700", hex: "#3F3F46", bg: "bg-zinc-700", fg: "text-white"},
      %{step: "800", hex: "#27272A", bg: "bg-zinc-800", fg: "text-white"},
      %{step: "900", hex: "#18181B", bg: "bg-zinc-900", fg: "text-white"}
    ]
  end

  @doc "Sample chart bars, one per country, in the country's color."
  def chart_bars do
    [
      %{name: "Denmark", bg: "bg-denmark-red", h: "h-[55%]"},
      %{name: "Finland", bg: "bg-finland-blue", h: "h-[72%]"},
      %{name: "Iceland", bg: "bg-iceland-blue", h: "h-[66%]"},
      %{name: "Norway", bg: "bg-norway-red", h: "h-full"},
      %{name: "Sweden", bg: "bg-sweden-yellow", h: "h-[86%]"}
    ]
  end

  @doc "Series colors for multi-series charts, in order."
  def series_colors do
    [
      %{n: 1, hex: "#005293", bg: "bg-sweden-blue"},
      %{n: 2, hex: "#C8102E", bg: "bg-denmark-red"},
      %{n: 3, hex: "#FECB00", bg: "bg-sweden-yellow"},
      %{n: 4, hex: "#002F6C", bg: "bg-finland-blue"}
    ]
  end
end
