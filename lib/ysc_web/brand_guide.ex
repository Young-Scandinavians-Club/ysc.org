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
  URL of Google's "Use template" page for the Slides template, or `nil` when no
  Slides file has been configured.
  """
  # Google file IDs are unreserved characters. Anything else is treated as
  # unset so a mistyped env value cannot inject `/`, `?`, or `#` into the path.
  @google_slides_id_pattern ~r/\A[A-Za-z0-9_-]+\z/

  def google_slides_template_url do
    case Application.get_env(:ysc, :brand_google_slides_template_id) do
      id when is_binary(id) and id != "" ->
        if Regex.match?(@google_slides_id_pattern, id) do
          encoded = URI.encode(id, &URI.char_unreserved?/1)
          "https://docs.google.com/presentation/d/#{encoded}/template/preview"
        else
          nil
        end

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
        ink: {"3.0", :large},
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
      %{step: "500", hex: "#2A9DFF", bg: "bg-blue-500", fg: "text-zinc-900"},
      %{step: "600", hex: "#1381FD", bg: "bg-blue-600", fg: "text-zinc-900"},
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

  @doc "Word / Google Docs template files, relative to `priv/static`."
  def document_template_files do
    [
      "documents/brand/YSC-document-template.docx",
      "documents/brand/YSC-document-template.dotx"
    ]
  end

  @doc "Palette files, relative to `priv/static`."
  def palette_files do
    for ext <- ~w(css json gpl ase), do: "documents/brand/ysc-palette.#{ext}"
  end

  @doc "Social and web image kit files, relative to `priv/static`."
  def social_kit_files do
    singles =
      for f <- [
            "ysc-profile-seal-white.png",
            "ysc-profile-seal-navy.png",
            "ysc-link-preview-1200x630.png",
            "ysc-social-kit.zip"
          ],
          do: "images/brand/kit/#{f}"

    canvases =
      for c <- canvases(), i <- c.items, do: String.trim_leading(i.href, "/")

    singles ++ canvases
  end

  def profile_pictures do
    [
      %{
        name: "Profile picture, white",
        description:
          "Seal on white. For Facebook, Instagram and other round avatars.",
        dark: false,
        href: kit_href("ysc-profile-seal-white.png")
      },
      %{
        name: "Profile picture, navy",
        description: "White-ring seal on navy. A good fit for dark interfaces.",
        dark: true,
        href: kit_href("ysc-profile-seal-navy.png")
      }
    ]
  end

  def link_preview do
    %{
      name: "Link preview image",
      description:
        "1200 × 630 px, the size used when a link is shared on Facebook, Slack, iMessage and LinkedIn.",
      href: kit_href("ysc-link-preview-1200x630.png")
    }
  end

  @canvas_sizes [
    {"square", "1080x1080", "Square 1080 × 1080"},
    {"landscape", "1200x630", "Landscape 1200 × 630"},
    {"story", "1080x1920", "Story 1080 × 1920"}
  ]

  @doc "Text-free post canvases, one set per Nordic country color."
  def canvases do
    for {name, slug, bg} <- [
          {"Denmark", "denmark", "bg-denmark-red"},
          {"Finland", "finland", "bg-finland-blue"},
          {"Iceland", "iceland", "bg-iceland-blue"},
          {"Norway", "norway", "bg-norway-blue"},
          {"Sweden", "sweden", "bg-sweden-yellow"}
        ] do
      %{
        name: name,
        slug: slug,
        bg: bg,
        items:
          for {kind, dims, label} <- @canvas_sizes do
            %{
              label: label,
              href: kit_href("ysc-canvas-#{kind}-#{dims}-#{slug}.png")
            }
          end
      }
    end
  end

  defp kit_href(file), do: ~p"/images/brand/kit/#{file}"

  def social_kit_zip_path, do: ~p"/images/brand/kit/ysc-social-kit.zip"

  @doc "Common image sizes. Platform sizes change, so treat these as a starting point."
  def image_sizes do
    [
      %{
        where: "Link preview (Open Graph)",
        size: "1200 × 630",
        note: "Facebook, LinkedIn, Slack, iMessage"
      },
      %{
        where: "Instagram or Facebook post",
        size: "1080 × 1080",
        note: "Square. 1080 × 1350 for a portrait post"
      },
      %{
        where: "Story or Reel",
        size: "1080 × 1920",
        note: "Keep text out of the top and bottom 250 px"
      },
      %{
        where: "Facebook event cover",
        size: "1920 × 1005",
        note: "Photo or color field with a short headline"
      },
      %{
        where: "Profile picture",
        size: "1080 × 1080",
        note: "Shown as a circle, so keep the seal centered"
      },
      %{
        where: "Email header or banner",
        size: "1200 px wide",
        note: "Shown at 600 px; keep it under 200 KB"
      },
      %{
        where: "Slides",
        size: "1920 × 1080",
        note: "16:9, the same as the slide template"
      },
      %{
        where: "A4 or US Letter",
        size: "2480 × 3508 / 2550 × 3300",
        note: "300 dpi, for print"
      }
    ]
  end

  @doc "HTML email signature (table layout and inline styles, as email apps require)."
  def email_signature_html do
    """
    <table cellpadding="0" cellspacing="0" border="0" style="font-family: Arial, Helvetica, sans-serif; font-size: 14px; color: #18181b;">
      <tr>
        <td style="padding-right: 16px; vertical-align: top;">
          <a href="https://ysc.org"><img src="https://ysc.org/images/brand/logos/ysc-logo-seal-white-center-512.png" width="96" alt="Young Scandinavians Club" style="display: block; border: 0;"></a>
        </td>
        <td style="vertical-align: top; line-height: 1.4;">
          <div style="font-size: 16px; font-weight: bold; color: #00205b;">Your Name</div>
          <div style="color: #52525b;">Your role, Young Scandinavians Club</div>
          <div style="margin-top: 6px;"><a href="mailto:you@ysc.org" style="color: #0c69e9; text-decoration: none;">you@ysc.org</a> &middot; <a href="https://ysc.org" style="color: #0c69e9; text-decoration: none;">ysc.org</a></div>
        </td>
      </tr>
    </table>
    """
    |> String.trim()
  end
end
