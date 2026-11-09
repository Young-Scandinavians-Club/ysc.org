# Brand & style guide

The public brand page lives at **`/brand`** (linked from the site footer). It shows the logo, Nordic colors, type, components, imagery and chart colors, and hosts downloads for people making documents, slides and web assets: logos, a PowerPoint template, a Word/Google Docs template, palette files, a social and web image kit, an email signature, and a pre-publish checklist.

## Where things are

| What | Where |
| --- | --- |
| Page template | `lib/ysc_web/controllers/page_html/brand.html.heex` |
| Controller action | `YscWeb.PageController.brand/2` |
| Colors, logo variants, chart colors | `lib/ysc_web/brand_guide.ex` |
| Logo files (SVG, PDF, PNG, AI, zip) | `priv/static/images/brand/logos/` |
| Slide template (.potx, .pptx) | `priv/static/documents/brand/` (see [presentation-template](../presentation-template/README.md)) |
| Document template (.dotx, .docx) | `priv/static/documents/brand/YSC-document-template.*` |
| Palette files (css, json, gpl, ase) | `priv/static/documents/brand/ysc-palette.*`, made by `etc/scripts/brand/make_palette.py` |
| Social and web image kit | `priv/static/images/brand/kit/`, made by `etc/scripts/brand/make_social_kit.sh` |
| Email signature, image sizes, checklist | `BrandGuide.email_signature_html/0`, `BrandGuide.image_sizes/0` and the template |
| Click-to-copy for swatches | `[data-brand-copy]` handler in `assets/js/app.js` |
| Tests | `describe "GET /brand"` in `test/ysc_web/controllers/page_controller_test.exs` |

The route is public (no sign-in) and the files are served as static assets, so nothing in these folders may be private.

## Keeping it in sync

The code is the source of truth. When these change, update the page:

- **Colors:** `assets/tailwind.config.js` (brand blue, blue scale, Nordic flag colors). Mirror changes in `BrandGuide`.
- **Type tokens:** the `TYPE TOKENS` block in `assets/css/app.css`. The page uses the real `type-*` classes, so it follows automatically.
- **Buttons and badges:** `lib/ysc_web/components/core_components.ex`. The page renders the real components.

Contrast ratios in the "Accessible pairings" table are WCAG 2.x values computed from the hex codes. Recompute them if a color changes.

## Logos

The five variants come from the Illustrator masters in the club's Box folder (`YSC LOGO`):

| Variant (file slug) | Box file |
| --- | --- |
| `seal-white-center` | `YSC LOGO 4 color 050125 - white background.ai` |
| `seal-transparent-center` | `YSC LOGO 4 color 052522.ai` |
| `seal-white-ring` | `YSC LOGO 4 color inverted circle 091222.ai` |
| `shield-white-text` | `YSC LOGO 4 color no circle background 091222.ai` |
| `stacked-white-text` | `YSC LOGO 4 color straight text 091222.ai` |

The `.ai` files are PDF-compatible, so the other formats were made with poppler's `pdftocairo`:

```bash
pdftocairo -svg master.ai ysc-logo-<slug>.svg
pdftocairo -pdf master.ai ysc-logo-<slug>.pdf
pdftocairo -png -transp -scale-to-x 2000 -scale-to-y -1 -singlefile master.ai ysc-logo-<slug>
pdftocairo -png -transp -scale-to-x 512 -scale-to-y -1 -singlefile master.ai ysc-logo-<slug>-512
```

`ysc-logos.zip` holds the SVG, PDF and PNG files of every variant (not the AI masters). To add a variant, add it to `BrandGuide.logo_variants/0`, drop its five files in `priv/static/images/brand/logos/`, and rebuild the zip.

## Document template

`YSC-document-template.docx` (and the `.dotx` template, which is the same file with a template content type) has the brand styles built in: Title, Subtitle, Heading 1 to 3, Quote, lists, tables, a header with the logo, a footer with page numbers, a meeting agenda and minutes page, and callouts in the five Nordic colors. It was generated with the `docx` npm library and imports cleanly into Google Docs. To change it, edit the `.docx` in Word, save, and export a copy as `.dotx`.

## Social and web kit

`make_social_kit.sh` builds the profile pictures, the 1200 × 630 link-preview image and 15 text-free post canvases (square, landscape and story sizes in the five country colors) from the logo files, plus `ysc-social-kit.zip`. It needs ImageMagick and `zip`.

```bash
etc/scripts/brand/make_social_kit.sh
python3 etc/scripts/brand/make_palette.py
```

If you change the palette, update `COLORS` in `make_palette.py` and the country list in `make_social_kit.sh`, then rerun both.

The email signature loads the logo from `https://ysc.org/images/brand/logos/ysc-logo-seal-white-center-512.png`, so its preview on `/brand` shows a broken image until this page is deployed to production.

## Google Slides button

The "Open in Google Slides" button on `/brand` appears only when `BRAND_GOOGLE_SLIDES_TEMPLATE_ID` is set (read in `config/runtime.exs`). To set it up:

1. Upload `YSC-presentation-template.pptx` to the club's Google Drive and open it with Google Slides.
2. Choose File, Save as Google Slides, then Share, General access: **Anyone with the link**, Viewer.
3. Copy the file ID from the URL (`docs.google.com/presentation/d/<ID>/edit`) and set `BRAND_GOOGLE_SLIDES_TEMPLATE_ID=<ID>` in production.

The button links to `.../presentation/d/<ID>/copy`, which asks the visitor to make their own copy in their Google account. After updating the template, repeat these steps; if the file ID changes, update the environment variable.

## What comes from the code and what is proposed

Colors, type tokens, button and badge styling come from the code above. The logo usage tips (clear space of about a quarter of the logo's width, darkening photos behind it) and the photo guidance are proposals, not existing brand rules.

## Related

- [Presentation template](../presentation-template/README.md): PowerPoint template that follows this guide.
