# YSC visual style guide

A single static page that shows how the club looks: logo, Nordic colors, type, components, imagery and chart colors.

Open [`index.html`](index.html) in a browser. There is no build step and no dependencies; the page uses the system font and loads nothing from the network.

## Files

| Path | What it is |
| --- | --- |
| `index.html` | The whole guide (HTML, CSS and a few lines of JS for copying hex codes) |
| `assets/ysc-logo.png` | Club seal, used on the page |
| `assets/ysc-logo-no-circle.svg` | Shield-only logo |
| `assets/bonfire.jpg` | Sample photo for the imagery section |

The logo and photo are copies of `priv/static/images/ysc_logo.png`, `ysc_logo_no_circle.svg` and `ysc_bonfire_2024.jpg`.

## Viewing it

Double-click `index.html`, or serve the folder:

```bash
python3 -m http.server 8000 --directory docs/style-guide
```

Then open <http://localhost:8000>. The "Slide template" links point at `../presentation-template/`, so they work when the whole `docs/` folder is served or opened from disk.

## Keeping it in sync

The code is the source of truth. If the page and the code disagree, the code wins. When these change, update the page:

- **Colors:** `assets/tailwind.config.js` (brand blue, blue scale, Nordic flag colors).
- **Type tokens:** the `TYPE TOKENS` block in `assets/css/app.css`.
- **Buttons, badges and form fields:** `lib/ysc_web/components/core_components.ex`.

Contrast ratios in the "Accessible pairings" table are WCAG 2.x values computed from the hex codes. Recompute them if a color changes.

## What comes from the code and what is proposed

Colors, type tokens, button and badge styling come from the code above. The logo rules (clear space of a quarter of the logo's width, minimum size of 48 px on screen and 15 mm in print) and the photo guidance are proposals, not taken from existing brand rules.

## Related

- [Presentation template](../presentation-template/README.md): PowerPoint template that follows this guide.
